"""SSH test runner for Cubie backend tests."""
import paramiko
import time
import sys


def ssh_run(client, cmd, timeout=180):
    stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    return exit_code, out, err


def main():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print("Connecting to 192.168.0.212...")
    client.connect("192.168.0.212", username="radxa", password="radxa", timeout=10)
    print("Connected.\n")

    venv = ". /home/radxa/AiHomeCloud/backend/venv/bin/activate"
    base = "cd /home/radxa/AiHomeCloud"

    # 1. Check service status
    print("=" * 60)
    print("1. SERVICE STATUS")
    print("=" * 60)
    code, out, err = ssh_run(client, "sudo systemctl status cubie-backend --no-pager -n 5", timeout=10)
    print(out or err)

    # 2. Run full pytest suite
    print("=" * 60)
    print("2. BACKEND PYTEST SUITE")
    print("=" * 60)
    code, out, err = ssh_run(client, f"{base} && {venv} && python -m pytest backend/tests/ -v --tb=short 2>&1", timeout=180)
    print(out)
    if err:
        print("STDERR:", err)
    print(f"Exit code: {code}")

    # 3. Live endpoint tests
    print("=" * 60)
    print("3. LIVE ENDPOINT TESTS")
    print("=" * 60)
    endpoints = [
        ("GET /", "curl -sk https://localhost:8443/"),
        ("GET /api/health", "curl -sk https://localhost:8443/api/health"),
        ("POST /api/v1/auth/login (admin)", 'curl -sk -X POST https://localhost:8443/api/v1/auth/login -H "Content-Type: application/json" -d \'{"username":"admin","pin":"1234"}\''),
        ("GET /api/v1/system/info (no auth)", "curl -sk https://localhost:8443/api/v1/system/info -w '\\nHTTP_STATUS:%{http_code}'"),
        ("Unauthenticated user create (C2 test)", 'curl -sk -X POST https://localhost:8443/api/v1/users -H "Content-Type: application/json" -d \'{"username":"hacker","pin":"0000"}\' -w \'\\nHTTP_STATUS:%{http_code}\''),
    ]
    for name, cmd in endpoints:
        code, out, err = ssh_run(client, cmd, timeout=10)
        print(f"\n  [{name}]")
        print(f"  {(out or err).strip()[:300]}")

    # 4. WebSocket test
    print("\n" + "=" * 60)
    print("4. WEBSOCKET /ws/monitor TEST")
    print("=" * 60)
    ws_test = (
        f"{venv} && python3 -c \""
        "import ssl, json;"
        "from websocket import create_connection;"
        "ws = create_connection('wss://localhost:8443/ws/monitor', sslopt={'cert_reqs': ssl.CERT_NONE}, timeout=8);"
        "data = ws.recv(); ws.close();"
        "parsed = json.loads(data);"
        "print('OK keys:', list(parsed.keys()))"
        "\""
    )
    code, out, err = ssh_run(client, ws_test, timeout=15)
    print(out or err)

    # 5. Recent logs
    print("=" * 60)
    print("5. RECENT JOURNAL LOGS (last 20 lines)")
    print("=" * 60)
    code, out, err = ssh_run(client, "sudo journalctl -u cubie-backend --no-pager -n 20", timeout=10)
    print(out or err)

    client.close()
    print("\nDone.")


if __name__ == "__main__":
    main()
