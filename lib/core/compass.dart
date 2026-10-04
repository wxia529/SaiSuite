// Preserve continuous rotation across magnetic north.
double unwrapHeading(double current, double target) =>
    current + ((target - current + 180) % 360) - 180;

String compassDirection(double degrees) => const [
  '北',
  '东北',
  '东',
  '东南',
  '南',
  '西南',
  '西',
  '西北',
][((degrees % 360 + 22.5) / 45).floor() % 8];
