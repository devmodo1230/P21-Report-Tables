"""
Pydantic schemas for request and response validation.
"""

from pydantic import BaseModel, field_validator


class TableCreate(BaseModel):
    table_name: str

    @field_validator("table_name")
    @classmethod
    def strip_and_validate(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("table_name must not be empty")
        return v


class ColumnCreate(BaseModel):
    column_name: str

    @field_validator("column_name")
    @classmethod
    def strip_and_validate(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("column_name must not be empty")
        return v


class BulkColumnCreate(BaseModel):
    columns: list[str]

    @field_validator("columns")
    @classmethod
    def strip_and_filter(cls, v: list[str]) -> list[str]:
        cleaned = [c.strip() for c in v if c.strip()]
        if not cleaned:
            raise ValueError("columns list must contain at least one non-empty name")
        return cleaned


class TableResponse(BaseModel):
    exists: bool
    id: int | None = None
    table_name: str
    created_at: str | None = None
    columns: list[str] = []
