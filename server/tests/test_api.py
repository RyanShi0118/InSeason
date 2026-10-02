import json

from fastapi.testclient import TestClient

from conftest import SAMPLE_HOUSEHOLD, FakeClient, text_message
from seasonbite_engine.api import app, get_client


def make_client(fake):
    app.dependency_overrides[get_client] = lambda: fake
    return TestClient(app)


def teardown_function():
    app.dependency_overrides.clear()


def test_returns_plan(sample_text, sample_plan):
    http = make_client(FakeClient([text_message(sample_text)]))
    response = http.post("/v1/meal-plans", json={"date": "2026-10-01", "household": SAMPLE_HOUSEHOLD})
    assert response.status_code == 200
    assert response.json() == sample_plan


def test_invalid_plan_is_502_with_errors(broken_plan):
    broken = json.dumps(broken_plan, ensure_ascii=False)
    http = make_client(FakeClient([text_message(broken), text_message(broken)]))
    response = http.post("/v1/meal-plans", json={"date": "2026-10-01", "household": SAMPLE_HOUSEHOLD})
    assert response.status_code == 502
    assert response.json()["detail"]["errors"]


def test_bad_request_is_422():
    http = make_client(FakeClient([]))
    response = http.post("/v1/meal-plans", json={"date": "not-a-date", "household": {"adults": 2}})
    assert response.status_code == 422


def test_app_token_is_enforced_when_set(monkeypatch, sample_text):
    monkeypatch.setenv("SEASONBITE_APP_TOKEN", "secret")
    http = make_client(FakeClient([text_message(sample_text)]))
    body = {"date": "2026-10-01", "household": SAMPLE_HOUSEHOLD}
    assert http.post("/v1/meal-plans", json=body).status_code == 401
    ok = http.post("/v1/meal-plans", json=body, headers={"Authorization": "Bearer secret"})
    assert ok.status_code == 200
