namespace Example;

/// <summary>
/// Provides basic arithmetic operations.
/// </summary>
public static class Calculator
{
  /// <summary>
  /// Adds two integers and returns the result.
  /// </summary>
  /// <param name="a">The first integer to add.</param>
  /// <param name="b">The second integer to add.</param>
  /// <returns>The sum of <paramref name="a"/> and <paramref name="b"/>.</returns>
  public static int Add(int a, int b) => a + b;

  /// <summary>
  /// Subtracts the second integer from the first and returns the result.
  /// </summary>
  /// <param name="a">The integer to subtract from.</param>
  /// <param name="b">The integer to subtract.</param>
  /// <returns>The result of <paramref name="a"/> minus <paramref name="b"/>.</returns>
  public static int Subtract(int a, int b) => a - b;

  /// <summary>
  /// Multiplies two integers and returns the result.
  /// </summary>
  /// <param name="a">The first integer to multiply.</param>
  /// <param name="b">The second integer to multiply.</param>
  /// <returns>The product of <paramref name="a"/> and <paramref name="b"/>.</returns>
  public static int Multiply(int a, int b) => a * b;

  /// <summary>
  /// Divides the first integer by the second and returns the result.
  /// </summary>
  /// <param name="a">The dividend.</param>
  /// <param name="b">The divisor.</param>
  /// <returns>The result of <paramref name="a"/> divided by <paramref name="b"/>.</returns>
  /// <exception cref="DivideByZeroException">Thrown when <paramref name="b"/> is zero.</exception>
  public static int Divide(int a, int b) => b == 0 ? throw new DivideByZeroException("Cannot divide by zero.") : a / b;
}
