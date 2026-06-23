namespace Example.Tests;

/// <summary>
/// Contains unit tests for the <see cref="Calculator"/> class.
/// </summary>
public class CalculatorTest
{
  /// <summary>
  /// Initializes a new instance of the <see cref="CalculatorTest"/> class.
  /// </summary>
  public CalculatorTest() { }

  /// <summary>
  /// Tests that Add returns the sum when given two integers.
  /// </summary>
  [Fact]
  public void Add_ShouldReturnSum_WhenGivenTwoIntegers()
  {
    // Arrange
    int a = 5;
    int b = 3;

    // Act
    int result = Calculator.Add(a, b);

    // Assert
    Assert.Equal(8, result);
  }

  /// <summary>
  /// Tests that Subtract returns the difference when given two integers.
  /// </summary>
  [Fact]
  public void Subtract_ShouldReturnDifference_WhenGivenTwoIntegers()
  {
    // Arrange
    int a = 10;
    int b = 4;

    // Act
    int result = Calculator.Subtract(a, b);

    // Assert
    Assert.Equal(6, result);
  }

  /// <summary>
  /// Tests that Multiply returns the product when given two integers.
  /// </summary>
  [Fact]
  public void Multiply_ShouldReturnProduct_WhenGivenTwoIntegers()
  {
    // Arrange
    int a = 7;
    int b = 6;

    // Act
    int result = Calculator.Multiply(a, b);

    // Assert
    Assert.Equal(42, result);
  }

  /// <summary>
  /// Tests that Divide returns the quotient when the divisor is not zero.
  /// </summary>
  [Fact]
  public void Divide_ShouldReturnQuotient_WhenDivisorIsNotZero()
  {
    // Arrange
    int a = 20;
    int b = 4;

    // Act
    int result = Calculator.Divide(a, b);

    // Assert
    Assert.Equal(5, result);
  }

  /// <summary>
  /// Tests that Divide throws a DivideByZeroException when the divisor is zero.
  /// </summary>
  [Fact]
  public void Divide_ShouldThrowDivideByZeroException_WhenDivisorIsZero()
  {
    // Arrange
    int a = 10;
    int b = 0;

    // Act & Assert
    var exception = Assert.Throws<DivideByZeroException>(() => Calculator.Divide(a, b));
    Assert.Equal("Cannot divide by zero.", exception.Message);
  }

  /// <summary>
  /// Tests that Add returns the expected result for various input values.
  /// </summary>
  /// <param name="a">The first integer to add.</param>
  /// <param name="b">The second integer to add.</param>
  /// <param name="expected">The expected sum of <paramref name="a"/> and <paramref name="b"/>.</param>
  [Theory]
  [InlineData(1, 2, 3)]
  [InlineData(-1, -1, -2)]
  [InlineData(0, 0, 0)]
  public void Add_ShouldReturnExpectedResult(int a, int b, int expected)
  {
    int result = Calculator.Add(a, b);
    Assert.Equal(expected, result);
  }

  /// <summary>
  /// Tests that Subtract returns the expected result for various input values.
  /// </summary>
  /// <param name="a">The first integer to subtract from.</param>
  /// <param name="b">The second integer to subtract.</param>
  /// <param name="expected">The expected difference of <paramref name="a"/> and <paramref name="b"/>.</param>
  [Theory]
  [InlineData(5, 3, 2)]
  [InlineData(-2, -2, 0)]
  [InlineData(0, 5, -5)]
  public void Subtract_ShouldReturnExpectedResult(int a, int b, int expected)
  {
    int result = Calculator.Subtract(a, b);
    Assert.Equal(expected, result);
  }

  /// <summary>
  /// Tests that Multiply returns the expected result for various input values.
  /// </summary>
  /// <param name="a">The first integer to multiply.</param>
  /// <param name="b">The second integer to multiply.</param>
  /// <param name="expected">The expected product of <paramref name="a"/> and <paramref name="b"/>.</param>
  [Theory]
  [InlineData(2, 3, 6)]
  [InlineData(-2, 3, -6)]
  [InlineData(0, 5, 0)]
  public void Multiply_ShouldReturnExpectedResult(int a, int b, int expected)
  {
    int result = Calculator.Multiply(a, b);
    Assert.Equal(expected, result);
  }

  /// <summary>
  /// Tests that Divide returns the expected result for various input values.
  /// </summary>
  /// <param name="a">The dividend.</param>
  /// <param name="b">The divisor.</param>
  /// <param name="expected">The expected quotient of <paramref name="a"/> and <paramref name="b"/>.</param>
  [Theory]
  [InlineData(6, 3, 2)]
  [InlineData(-6, 3, -2)]
  [InlineData(0, 1, 0)]
  public void Divide_ShouldReturnExpectedResult(int a, int b, int expected)
  {
    int result = Calculator.Divide(a, b);
    Assert.Equal(expected, result);
  }
}
