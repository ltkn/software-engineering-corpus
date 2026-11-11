package limiter

import (
	"sync"
	"time"
)

type Clock func() time.Time

type Limiter struct {
	mu       sync.Mutex
	tokens   float64
	capacity float64
	rate     float64
	last     time.Time
	now      Clock
}

func New(capacity int, perSecond float64, now Clock) *Limiter {
	return &Limiter{tokens: float64(capacity), capacity: float64(capacity), rate: perSecond, last: now(), now: now}
}

func (l *Limiter) Allow() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	t := l.now()
	l.tokens += t.Sub(l.last).Seconds() * l.rate
	if l.tokens > l.capacity {
		l.tokens = l.capacity
	}
	l.last = t
	if l.tokens >= 1 {
		l.tokens--
		return true
	}
	return false
}
