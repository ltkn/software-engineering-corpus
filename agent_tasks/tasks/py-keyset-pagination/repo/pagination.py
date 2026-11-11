from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class User:
    id: int
    created_at: datetime
    email: str


def page_after(users: list[User], cursor: tuple[datetime, int] | None, limit: int) -> tuple[list[User], tuple[datetime, int] | None]:
    """Return up to `limit` users after `cursor`, ordered by (created_at, id), and the next cursor."""
    ordered = sorted(users, key=lambda u: u.created_at)
    if cursor is not None:
        ordered = [u for u in ordered if u.created_at >= cursor[0]]
    page = ordered[:limit]
    next_cursor = (page[-1].created_at, page[-1].id) if len(page) == limit else None
    return page, next_cursor
