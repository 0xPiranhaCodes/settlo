import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The server refuses an RPC with Postgres [code] and [hint].
final class Refuse {
  const new(this.code, {this.hint, this.status = 400});

  final String? code;
  final String? hint;
  final int status;
}

/// The server does the work but the response never arrives.
const lost = #lost;

typedef Rows = List<Map<String, Object?>>;

/// A PostgREST stand-in on loopback: GETs read [tables] (with `eq.`
/// filters), RPCs go to [rpc]. Every RPC is logged in [calls].
final class FakeServer {
  final tables = <String, Rows>{};
  final calls = <(String, Map<String, dynamic>)>[];

  /// Answers an RPC: a value to send as JSON, a [Refuse], or [lost].
  Object? Function(String fn, Map<String, dynamic> body) rpc = (_, _) => null;

  /// A status for every GET; 200 serves [tables].
  int readStatus = 200;

  /// Called on every GET.
  void Function() onRead = () {};

  late final HttpServer _server;
  late final SupabaseClient client;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
    client = SupabaseClient(
      'http://${_server.address.host}:${_server.port}',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }

  Future<void> stop() async {
    await client.dispose();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final path = request.uri.path.replaceFirst('/rest/v1/', '');
    final response = request.response..headers.contentType = ContentType.json;
    if (path.startsWith('rpc/')) {
      final fn = path.substring(4);
      final params = jsonDecode(body) as Map<String, dynamic>;
      calls.add((fn, params));
      switch (rpc(fn, params)) {
        case lost:
          (await response.detachSocket()).destroy();
          return;
        case Refuse(:final code, :final hint, :final status):
          response
            ..statusCode = status
            ..write(
              jsonEncode({'code': code, 'hint': hint, 'message': 'refused'}),
            );
        case final value:
          response.write(jsonEncode(value));
      }
    } else if (readStatus != 200) {
      onRead();
      response
        ..statusCode = readStatus
        ..write(jsonEncode({'message': 'down'}));
    } else {
      onRead();
      final filters = {
        for (final MapEntry(:key, :value)
            in request.uri.queryParameters.entries)
          if (value.startsWith('eq.')) key: value.substring(3),
      };
      response.write(
        jsonEncode([
          for (final row in tables[path] ?? const <Map<String, Object?>>[])
            if (filters.entries.every((f) => '${row[f.key]}' == f.value)) row,
        ]),
      );
    }
    await response.close();
  }
}
