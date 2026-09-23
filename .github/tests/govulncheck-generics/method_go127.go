//go:build go1.27

package main

import "fmt"

type transform struct{}

// Generic methods require Go 1.27. Keep this in the scanned call graph so an
// obsolete scanner cannot pass merely because no vulnerable dependency exists.
func (transform) apply[T any](value T, f func(T) T) T { return f(value) }

func init() {
	fmt.Println(transform{}.apply(1, func(n int) int { return n + 1 }))
}
