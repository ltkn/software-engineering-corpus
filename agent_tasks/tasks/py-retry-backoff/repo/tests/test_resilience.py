import pytest
from resilience import RetryError, retry


def flaky(failures, exc=ConnectionError):
    state = {"n": 0}

    def fn():
        state["n"] += 1
        if state["n"] <= failures:
            raise exc("boom")
        return "ok"
    return fn, state


def test_succeeds_after_failures_with_jittered_delays():
    sleeps = []
    fn, state = flaky(2)
    assert retry(fn, sleep=sleeps.append, rand=lambda: 0.5) == "ok"
    assert state["n"] == 3
    assert sleeps == pytest.approx([0.1, 0.2])


def test_delay_is_capped():
    sleeps = []
    fn, _ = flaky(10)
    with pytest.raises(RetryError):
        retry(fn, attempts=6, base=1.0, cap=3.0, sleep=sleeps.append, rand=lambda: 1.0)
    assert sleeps == pytest.approx([1.0, 2.0, 3.0, 3.0, 3.0])


def test_non_retryable_propagates_at_once():
    sleeps = []
    fn, state = flaky(1, exc=ValueError)
    with pytest.raises(ValueError):
        retry(fn, sleep=sleeps.append)
    assert state["n"] == 1 and sleeps == []


def test_retry_error_keeps_last_exception():
    fn, _ = flaky(10, exc=TimeoutError)
    with pytest.raises(RetryError) as info:
        retry(fn, attempts=2, sleep=lambda s: None)
    assert isinstance(info.value.last, TimeoutError)
