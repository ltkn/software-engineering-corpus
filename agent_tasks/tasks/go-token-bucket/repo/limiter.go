package limiter

import "time"

// Clock returns the current time; tests inject a fake one.
type Clock func() time.Time

type Limiter struct{}

// New returns a limiter with `capacity` tokens, refilled at `perSecond`.
func New(capacity int, perSecond float64, now Clock) *Limiter {
	panic("not implemented")
}

// Allow takes one token if available.
func (l *Limiter) Allow() bool {
	panic("not implemented")
}
