"""
Visitor Counter Web Application – Extended Analytics Backend
Flask + Redis  |  Cloud Computing Project
"""

import os
import time
import platform
import logging
import datetime
from flask import Flask, render_template, jsonify, request
import redis

# ── Logging ────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ── Flask app ───────────────────────────────────────────────────────────────
app = Flask(__name__)
APP_START_TIME = time.time()

# ── Redis config ────────────────────────────────────────────────────────────
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
REDIS_DB   = int(os.environ.get("REDIS_DB", 0))
APP_TITLE  = os.environ.get("APP_TITLE", "Cloud Visitor Counter")

redis_client = None


def get_redis():
    """Return a live Redis client, or None on failure."""
    global redis_client
    try:
        if redis_client is None:
            redis_client = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                db=REDIS_DB,
                socket_connect_timeout=3,
                socket_timeout=3,
                decode_responses=True,
            )
        redis_client.ping()
        return redis_client
    except redis.RedisError as exc:
        logger.warning("Redis unavailable: %s", exc)
        redis_client = None
        return None


def today_key():
    """Redis key for today's visitor count  e.g. visitors:2024-11-23"""
    return "visitors:" + datetime.date.today().isoformat()


def record_visit(r):
    """Increment total + today counters; push a timestamped activity entry."""
    total = r.incr("visitor_count")
    r.incr(today_key())
    # Keep today's key for 7 days
    r.expire(today_key(), 7 * 24 * 3600)

    # Recent-activity log (capped at 50 entries)
    entry = f"{time.time():.0f}|{request.path}|{request.method}"
    r.lpush("recent_activity", entry)
    r.ltrim("recent_activity", 0, 49)

    return total


# ── Routes ──────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    """Main dashboard page – also counts the visit."""
    r = get_redis()
    if r:
        try:
            count        = record_visit(r)
            redis_status = "connected"
            logger.info("Visitor #%s", count)
        except redis.RedisError as exc:
            count        = "N/A"
            redis_status = "error"
            logger.error("Redis error: %s", exc)
    else:
        count        = "N/A"
        redis_status = "disconnected"

    return render_template(
        "index.html",
        visitor_count=count,
        redis_status=redis_status,
        redis_host=REDIS_HOST,
        app_title=APP_TITLE,
    )


# ── Existing probes (unchanged) ─────────────────────────────────────────────

@app.route("/health")
def health():
    """Liveness probe – 200 as long as Flask is alive."""
    return jsonify({"status": "healthy", "service": "flask-visitor-counter"}), 200


@app.route("/ready")
def ready():
    """Readiness probe – 200 only when Redis is reachable."""
    r = get_redis()
    if r:
        return jsonify({"status": "ready", "redis": "connected"}), 200
    return jsonify({"status": "not ready", "redis": "disconnected"}), 503


@app.route("/stats")
def stats():
    """Current visitor count as JSON."""
    r = get_redis()
    if r:
        try:
            count = int(r.get("visitor_count") or 0)
            return jsonify({"visitor_count": count, "redis": "connected"}), 200
        except redis.RedisError as exc:
            return jsonify({"error": str(exc), "redis": "error"}), 500
    return jsonify({"visitor_count": "N/A", "redis": "disconnected"}), 503


@app.route("/reset", methods=["POST"])
def reset():
    """Reset the visitor counter to 0."""
    r = get_redis()
    if r:
        try:
            r.set("visitor_count", 0)
            return jsonify({"status": "reset", "visitor_count": 0}), 200
        except redis.RedisError as exc:
            return jsonify({"error": str(exc)}), 500
    return jsonify({"error": "Redis not available"}), 503


# ── NEW: Analytics API endpoints ────────────────────────────────────────────

@app.route("/api/dashboard")
def api_dashboard():
    """
    Single endpoint the dashboard polls every 10 s.
    Returns all KPIs, daily trend (last 7 days), recent activity,
    and infrastructure status – sourced entirely from real data.
    """
    r = get_redis()

    # ── Visitor counts ───────────────────────────────────────────────────
    if r:
        try:
            total_visitors = int(r.get("visitor_count") or 0)
            today_visitors = int(r.get(today_key()) or 0)
            redis_ok       = True
            redis_info     = r.info("server")
            redis_version  = redis_info.get("redis_version", "unknown")
            redis_uptime   = redis_info.get("uptime_in_seconds", 0)
        except redis.RedisError:
            total_visitors = 0
            today_visitors = 0
            redis_ok       = False
            redis_version  = "unknown"
            redis_uptime   = 0
    else:
        total_visitors = 0
        today_visitors = 0
        redis_ok       = False
        redis_version  = "unknown"
        redis_uptime   = 0

    # ── 7-day daily trend ────────────────────────────────────────────────
    daily_trend = []
    for delta in range(6, -1, -1):          # oldest first
        d   = datetime.date.today() - datetime.timedelta(days=delta)
        key = "visitors:" + d.isoformat()
        if r and redis_ok:
            try:
                val = int(r.get(key) or 0)
            except Exception:
                val = 0
        else:
            val = 0
        daily_trend.append({"date": d.isoformat(), "count": val})

    # Average daily (non-zero days only)
    non_zero = [d["count"] for d in daily_trend if d["count"] > 0]
    avg_daily = round(sum(non_zero) / len(non_zero), 1) if non_zero else 0

    # ── Recent activity ──────────────────────────────────────────────────
    activity = []
    if r and redis_ok:
        try:
            raw = r.lrange("recent_activity", 0, 14)
            for item in raw:
                parts = item.split("|")
                if len(parts) == 3:
                    ts, path, method = parts
                    activity.append({
                        "timestamp": int(float(ts)),
                        "path":      path,
                        "method":    method,
                    })
        except Exception:
            pass

    # ── Infrastructure ───────────────────────────────────────────────────
    uptime_sec  = int(time.time() - APP_START_TIME)
    uptime_hrs  = uptime_sec // 3600
    uptime_mins = (uptime_sec % 3600) // 60

    infra = {
        "flask": {
            "status":       "running",
            "uptime_sec":   uptime_sec,
            "uptime_label": f"{uptime_hrs}h {uptime_mins}m",
            "python":       platform.python_version(),
            "platform":     platform.system(),
            "host":         os.environ.get("HOSTNAME", "localhost"),
        },
        "redis": {
            "status":    "connected" if redis_ok else "disconnected",
            "host":      REDIS_HOST,
            "port":      REDIS_PORT,
            "version":   redis_version,
            "uptime_sec": redis_uptime,
        },
        "env": {
            "app_title":   APP_TITLE,
            "redis_host":  REDIS_HOST,
            "flask_port":  os.environ.get("FLASK_PORT", "5000"),
            "kubernetes":  os.path.exists("/var/run/secrets/kubernetes.io"),
            "docker":      os.path.exists("/.dockerenv"),
        },
    }

    return jsonify({
        "kpis": {
            "total_visitors": total_visitors,
            "today_visitors": today_visitors,
            "avg_daily":      avg_daily,
            "redis_ok":       redis_ok,
        },
        "daily_trend":     daily_trend,
        "recent_activity": activity,
        "infrastructure":  infra,
        "server_time":     datetime.datetime.utcnow().isoformat() + "Z",
    })


@app.route("/api/visit", methods=["POST"])
def api_visit():
    """
    Lightweight AJAX visit recorder – increments counter without
    doing a full page reload. Used by the dashboard's auto-refresh.
    """
    r = get_redis()
    if r:
        try:
            total = record_visit(r)
            return jsonify({"visitor_count": total, "redis": "connected"}), 200
        except redis.RedisError as exc:
            return jsonify({"error": str(exc)}), 500
    return jsonify({"error": "Redis not available"}), 503


# ── Entry point ─────────────────────────────────────────────────────────────
if __name__ == "__main__":
    port  = int(os.environ.get("FLASK_PORT", 5000))
    debug = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
    logger.info("Starting %s on port %s", APP_TITLE, port)
    app.run(host="0.0.0.0", port=port, debug=debug)
