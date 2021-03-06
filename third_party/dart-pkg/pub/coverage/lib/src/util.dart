// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library coverage.src.util;

import 'dart:async';
import 'dart:io';

/// Retries the specified function with the specified interval and returns
/// the result on successful completion.
Future retry(Future f(), Duration interval, {Duration timeout}) async {
  var keepGoing = true;

  Future _withTimeout(Future f(), {Duration duration}) {
    if (duration == null) {
      return f();
    }

    return f().timeout(duration, onTimeout: () {
      keepGoing = false;

      var msg;

      if (duration.inSeconds == 0) {
        msg = '${duration.inMilliseconds}ms';
      } else {
        msg = '${duration.inSeconds}s';
      }

      throw new StateError('Failed to complete within ${msg}');
    });
  }

  return _withTimeout(() async {
    while (keepGoing) {
      try {
        var result = await f();
        return result;
      } catch (_) {
        if (keepGoing) {
          await new Future.delayed(interval);
        }
      }
    }
  }, duration: timeout);
}

/// Scrapes and returns the observatory URI from a string, or null if not found.
///
/// Potentially useful as a means to extract it from log statements.
Uri extractObservatoryUri(String str) {
  const kObservatoryListening = 'Observatory listening on ';
  int msgPos = str.indexOf(kObservatoryListening);
  if (msgPos == -1) return null;
  int startPos = msgPos + kObservatoryListening.length;
  int endPos = str.indexOf(new RegExp(r'(\s|$)'), startPos);
  try {
    return Uri.parse(str.substring(startPos, endPos));
  } on FormatException {
    return null;
  }
}

/// Returns an open port by creating a temporary Socket
Future<int> getOpenPort() async {
  ServerSocket socket;

  try {
    socket = await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V4, 0);
  } catch (_) {
    // try again v/ V6 only. Slight possibility that V4 is disabled
    socket = await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V6, 0,
        v6Only: true);
  }

  try {
    return socket.port;
  } finally {
    await socket.close();
  }
}
