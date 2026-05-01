"""
Pydantic schemas for request and response validation.
"""

from pydantic import BaseModel, field_validator


def _validate_report_name(v: str) -> str:
    v = v.strip()
    if not v:
        raise ValueError("report_name must not be empty")
    return v


class TableCreate(BaseModel):
    report_name: str
    table_name: str

    @field_validator("report_name")
    @classmethod
    def validate_report_name(cls, v: str) -> str:
        return _validate_report_name(v)

    @field_validator("table_name")
    @classmethod
    def strip_and_validate_table(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("table_name must not be empty")
        return v


class ColumnCreate(BaseModel):
    report_name: str
    column_name: str

    @field_validator("report_name")
    @classmethod
    def validate_report_name(cls, v: str) -> str:
        return _validate_report_name(v)

    @field_validator("column_name")
    @classmethod
    def strip_and_validate_column(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("column_name must not be empty")
        return v


class BulkColumnCreate(BaseModel):
    report_name: str
    columns: list[str]

    @field_validator("report_name")
    @classmethod
    def validate_report_name(cls, v: str) -> str:
        return _validate_report_name(v)

    @field_validator("columns")
    @classmethod
    def strip_and_filter(cls, v: list[str]) -> list[str]:
        cleaned = [c.strip() for c in v if c.strip()]
        if not cleaned:
            raise ValueError("columns list must contain at least one non-empty name")
        return cleaned


class ParseSqlRequest(BaseModel):
    report_name: str
    sql: str

    @field_validator("report_name")
    @classmethod
    def validate_report_name(cls, v: str) -> str:
        return _validate_report_name(v)

    @field_validator("sql")
    @classmethod
    def strip_and_validate_sql(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("sql must not be empty")
        return v


class ParsedTable(BaseModel):
    table_name: str
    alias: str
    columns: list[str]


class ParseSqlResponse(BaseModel):
    report_name: str
    tables: list[ParsedTable]
    warnings: list[str]
