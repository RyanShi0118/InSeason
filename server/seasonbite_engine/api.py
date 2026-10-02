"""HTTP API the iOS app calls. The Anthropic API key stays on this server.

Run locally: uvicorn seasonbite_engine.api:app --app-dir server
"""
import datetime
import hmac
import os

import anthropic
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from .engine import MealPlanError, generate_meal_plan

app = FastAPI(title="SeasonBite recipe engine")


class ChildIn(BaseModel):
    age_years: float = Field(ge=0.5, le=17)
    allergies: list[str] = []


class HouseholdIn(BaseModel):
    adults: int = Field(ge=0, le=12)
    children: list[ChildIn] = Field(default=[], max_length=8)


class MealPlanRequest(BaseModel):
    date: datetime.date
    household: HouseholdIn


def get_client():
    return anthropic.Anthropic()


def check_app_token(authorization: str | None = Header(default=None)):
    """When SEASONBITE_APP_TOKEN is set, requests must send it as a bearer token."""
    token = os.environ.get("SEASONBITE_APP_TOKEN")
    if not token:
        return
    if not authorization or not hmac.compare_digest(authorization, f"Bearer {token}"):
        raise HTTPException(status_code=401, detail="Missing or wrong app token")


@app.get("/healthz")
def healthz():
    return {"ok": True}


@app.post("/v1/meal-plans", dependencies=[Depends(check_app_token)])
def create_meal_plan(request: MealPlanRequest, client: anthropic.Anthropic = Depends(get_client)):
    try:
        return generate_meal_plan(request.date.isoformat(), request.household.model_dump(), client)
    except MealPlanError as e:
        raise HTTPException(status_code=502, detail={"message": str(e), "errors": e.errors})
    except anthropic.RateLimitError:
        raise HTTPException(status_code=503, detail="Recipe engine is busy, try again shortly")
    except (anthropic.APIStatusError, anthropic.APIConnectionError):
        raise HTTPException(status_code=502, detail="Recipe engine could not reach the model")
