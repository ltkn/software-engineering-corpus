package limiter

import (
	"sync"
	"testing"
	"time"
)

type fake struct{ t time.Time }

func (f *fake) now() time.Time { return f.t }

func TestBurstThenRefill(t *testing.T) {
	f := &fake{t: time.Unix(0, 0)}
	l := New(3, 2, f.now)
	for i := 0; i < 3; i++ {
		if !l.Allow() {
			t.Fatalf("burst token %d denied", i)
		}
	}
	if l.Allow() {
		t.Fatal("4th token allowed without refill")
	}
	f.t = f.t.Add(500 * time.Millisecond) // +1 token
	if !l.Allow() || l.Allow() {
		t.Fatal("expected exactly one refilled token")
	}
	f.t = f.t.Add(10 * time.Second) // refill caps at capacity
	n := 0
	for l.Allow() {
		n++
	}
	if n != 3 {
		t.Fatalf("refill not capped: %d", n)
	}
}

func TestConcurrent(t *testing.T) {
	f := &fake{t: time.Unix(0, 0)}
	l := New(100, 0, f.now)
	var wg sync.WaitGroup
	var mu sync.Mutex
	allowed := 0
	for g := 0; g < 10; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 50; i++ {
				if l.Allow() {
					mu.Lock()
					allowed++
					mu.Unlock()
				}
			}
		}()
	}
	wg.Wait()
	if allowed != 100 {
		t.Fatalf("allowed %d, want 100", allowed)
	}
}
