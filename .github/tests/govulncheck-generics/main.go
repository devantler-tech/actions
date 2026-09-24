// Package main exercises generic instantiation and the Go 1.27 generic methods
// exposed by math/rand/v2, which older scanner type walkers cannot traverse.
package main

import (
	"fmt"
	"math/rand/v2"

	"golang.org/x/text/language"
)

type box[T any] struct{ value T }

func (b box[T]) get() T { return b.value }

func mapValue[T, U any](b box[T], f func(T) U) box[U] {
	return box[U]{value: f(b.get())}
}

func main() {
	r := rand.New(rand.NewPCG(1, 2))
	// Passing Rand through an interface forces analysis of its method set,
	// including the generic Rand.N method added in Go 1.27.
	fmt.Printf("%T\n", r)
	b := mapValue(box[int]{value: r.IntN(10)}, func(n int) string {
		return fmt.Sprint(n)
	})
	fmt.Println(b.get())
	// A vulnerable dependency is necessary: without one, the scanner can skip
	// call-graph construction and falsely appear compatible with this program.
	tag, err := language.Parse("en-US")
	fmt.Println(tag, err)
}
