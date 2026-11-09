/// An amount of money in paise (1/100 rupee).
///
/// Money is always an integer number of paise; there is deliberately no
/// conversion to or from `double`.
extension type const Paise(int value) {
  /// Whole [rupees], i.e. `rupees * 100` paise.
  const new rupees(int rupees) : this(rupees * 100);

  /// No money.
  static const zero = Paise(0);

  /// Sum of two amounts.
  Paise operator +(Paise other) => Paise(value + other.value);

  /// Difference of two amounts.
  Paise operator -(Paise other) => Paise(value - other.value);

  /// The amount with its sign flipped.
  Paise operator -() => Paise(-value);
}
