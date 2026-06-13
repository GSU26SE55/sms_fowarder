class PhoneNumberUtils {
  PhoneNumberUtils._();

  /// Chuẩn hóa số điện thoại Việt Nam.
  /// Trả về dạng quốc tế `+84xxxxxxxxx` nếu nhận diện được, ngược lại
  /// trả về số đã loại ký tự thừa.
  static String normalizeVn(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (s.isEmpty) return s;

    if (s.startsWith('+')) return s;

    // 84xxxxxxxxx -> +84xxxxxxxxx
    if (s.startsWith('84') && s.length >= 11) {
      return '+$s';
    }

    // 0xxxxxxxxx -> +84xxxxxxxxx
    if (s.startsWith('0') && s.length == 10) {
      return '+84${s.substring(1)}';
    }

    return s;
  }

  /// Kiểm tra số điện thoại có dạng hợp lệ tối thiểu (chỉ số + dấu +,
  /// độ dài 9-15).
  static bool isValid(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    final re = RegExp(r'^\+?[0-9]{9,15}$');
    return re.hasMatch(s);
  }
}
