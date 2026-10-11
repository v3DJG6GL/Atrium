import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

typedef ResponseFactory = ({int status, Object? data}) Function(
  RequestOptions options,
);

/// A response body sent as-is instead of JSON-encoded, with an explicit
/// content type (e.g. an empty 204 labelled JSON, or an HTML page).
class RawBody {
  const RawBody(this.body, {this.contentType});

  final String body;

  /// Null sends no content type at all.
  final String? contentType;
}

class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this.responseFactory, {this.headersFactory});

  final ResponseFactory responseFactory;
  final Map<String, List<String>> Function(RequestOptions options)?
      headersFactory;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final ({Object? data, int status}) response = responseFactory(options);
    final Object? data = response.data;
    if (data is RawBody) {
      return ResponseBody.fromString(
        data.body,
        response.status,
        headers: <String, List<String>>{
          if (data.contentType != null)
            Headers.contentTypeHeader: <String>[data.contentType!],
          ...?headersFactory?.call(options),
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      response.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        ...?headersFactory?.call(options),
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
