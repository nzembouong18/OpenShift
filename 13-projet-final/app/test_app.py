import app as vote_app


def client():
    vote_app.app.config["TESTING"] = True
    return vote_app.app.test_client()


def test_healthz():
    r = client().get("/healthz")
    assert r.status_code == 200
    assert r.get_json() == {"status": "ok"}


def test_vote_rejects_invalid_choice():
    r = client().post("/api/vote", json={"choice": "z"})
    assert r.status_code == 400


def test_metrics_exposes_counter():
    c = client()
    c.get("/healthz")
    body = c.get("/metrics").get_data(as_text=True)
    assert 'http_requests_total{path="/healthz",status="200"}' in body
