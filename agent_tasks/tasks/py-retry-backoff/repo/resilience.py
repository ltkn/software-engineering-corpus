import random
import time


class RetryError(Exception):
    """Raised when every attempt failed; `last` holds the last exception."""

    def __init__(self, last: Exception):
        super().__init__(f"all attempts failed: {last!r}")
        self.last = last


def retry(fn, *, attempts=4, base=0.2, cap=5.0, retry_on=(ConnectionError, TimeoutError),
          sleep=time.sleep, rand=random.random):
    """Call fn() until it succeeds.

    - at most `attempts` calls in total
    - only exceptions in `retry_on` are retried; anything else propagates immediately
    - before retry n (n = 1, 2, ...) sleep for a "full jitter" delay:
      rand() * min(cap, base * 2 ** (n - 1))
    - if every attempt fails, raise RetryError with the last exception
    """
    raise NotImplementedError
