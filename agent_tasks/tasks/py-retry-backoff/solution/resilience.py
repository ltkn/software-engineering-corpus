import random
import time


class RetryError(Exception):
    """Raised when every attempt failed; `last` holds the last exception."""

    def __init__(self, last: Exception):
        super().__init__(f"all attempts failed: {last!r}")
        self.last = last


def retry(fn, *, attempts=4, base=0.2, cap=5.0, retry_on=(ConnectionError, TimeoutError),
          sleep=time.sleep, rand=random.random):
    last = None
    for n in range(attempts):
        if n:
            sleep(rand() * min(cap, base * 2 ** (n - 1)))
        try:
            return fn()
        except retry_on as e:
            last = e
    raise RetryError(last)
