/// Reject empty output, including literal escaped newlines, without rewriting
/// valid JSON strings or code in a model reply.
bool hasModelContent(String output) =>
    output.replaceAll(RegExp(r'\\[nrt]'), '').trim().isNotEmpty;
