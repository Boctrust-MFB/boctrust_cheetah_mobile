/// Whether [number] is an 11-digit mobile number starting with 0, the form
/// billers take for airtime and data. Separate from signup's
/// `isValidNigerianPhone`, which also accepts international formats that the
/// bill flow sends as typed.
bool isValidBillMobileNumber(String number) =>
    RegExp(r'^0\d{10}$').hasMatch(number);
