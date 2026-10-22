import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GithubBuilderService {
  static const _clientId = 'Ov23lihhpWRfaAFd95ao';
  static const _templateRepo = 'IILLUMINATION/mnd-standalone-builder';

  String? _accessToken;
  int _wfRetryCount = 0;

  Future<bool> get hasToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('github_builder_token');
  }

  Future<void> _loadToken() async {
    if (_accessToken != null) return;
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('github_builder_token');
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('github_builder_token', token);
    _accessToken = token;
  }

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $_accessToken',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  // ─── Device Flow Auth ─────────────────────────────────────────

  Future<Map<String, dynamic>> startDeviceAuth() async {
    final response = await http.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {'Accept': 'application/json'},
      body: {
        'client_id': _clientId,
        'scope': 'repo workflow',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Device auth failed: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<bool> pollDeviceAuth(String deviceCode) async {
    const maxTries = 40;
    const interval = Duration(seconds: 5);

    for (var i = 0; i < maxTries; i++) {
      await Future.delayed(interval);

      final response = await http.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {'Accept': 'application/json'},
        body: {
          'client_id': _clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );

      if (response.statusCode != 200) continue;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final error = data['error'] as String?;

      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        await Future.delayed(const Duration(seconds: 5));
        continue;
      }
      if (error != null) return false;

      final token = data['access_token'] as String?;
      if (token != null) {
        await _saveToken(token);
        return true;
      }
    }
    return false;
  }

  // ─── Repo Operations ──────────────────────────────────────────

  Future<String> getUsername() async {
    await _loadToken();
    final response = await http.get(
      Uri.parse('https://api.github.com/user'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to get user: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['login'] as String;
  }

  Future<bool> forkRepo() async {
    await _loadToken();
    final username = await getUsername();
    final repoName = 'mnd-standalone-builder';
    final targetRepo = '$username/$repoName';

    final check = await http.get(
      Uri.parse('https://api.github.com/repos/$targetRepo'),
      headers: _headers,
    );
    if (check.statusCode == 200) {
      final data = jsonDecode(check.body) as Map<String, dynamic>;
      final isFork = data['fork'] as bool? ?? false;
      if (!isFork) return true;
      // Fork exists — can't delete without admin. Use it as-is.
      return true;
    }

    final response = await http.post(
      Uri.parse('https://api.github.com/repos/$_templateRepo/generate'),
      headers: _headers,
      body: jsonEncode({
        'owner': username,
        'name': repoName,
        'description': 'Cloud-built Meander quest app',
        'include_all_branches': false,
        'private': false,
      }),
    );

    if (response.statusCode == 422) {
      await Future.delayed(const Duration(seconds: 3));
      final retry = await http.get(
        Uri.parse('https://api.github.com/repos/$targetRepo'),
        headers: _headers,
      );
      if (retry.statusCode == 200) return true;
      throw Exception('Failed to create repo from template: ${response.body}');
    }

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Template generation failed: ${response.body}');
    }

    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 3));
      final statusCheck = await http.get(
        Uri.parse('https://api.github.com/repos/$targetRepo'),
        headers: _headers,
      );
      if (statusCheck.statusCode == 200) return true;
    }

    throw Exception('Repo generation did not complete in time');
  }

  Future<String> getDefaultBranch() async {
    await _loadToken();
    final username = await getUsername();
    final targetRepo = '$username/mnd-standalone-builder';

    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$targetRepo'),
      headers: _headers,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to get repo: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['default_branch'] as String? ?? 'master';
  }

  Future<void> uploadFile(String path, String content) async {
    await _loadToken();
    final username = await getUsername();
    final targetRepo = '$username/mnd-standalone-builder';
    final branch = await getDefaultBranch();

    final encoded = base64Encode(utf8.encode(content));

    String? sha;
    try {
      final getResponse = await http.get(
        Uri.parse(
          'https://api.github.com/repos/$targetRepo/contents/$path?ref=$branch',
        ),
        headers: _headers,
      );
      if (getResponse.statusCode == 200) {
        final data = jsonDecode(getResponse.body) as Map<String, dynamic>;
        sha = data['sha'] as String?;
      }
    } catch (_) {}

    final body = {
      'message': 'Upload $path',
      'content': encoded,
      'branch': branch,
    };
    if (sha != null) body['sha'] = sha;

    final response = await http.put(
      Uri.parse('https://api.github.com/repos/$targetRepo/contents/$path'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Upload failed: ${response.body}');
    }
  }

  // ─── Workflow Dispatch ─────────────────────────────────────────

  Future<dynamic> _getWorkflowId(String targetRepo) async {
    await _loadToken();
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$targetRepo/actions/workflows'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to list workflows: ${response.body}');
    }

    final workflowsData =
        jsonDecode(response.body) as Map<String, dynamic>;
    final workflows =
        workflowsData['workflows'] as List<dynamic>? ?? [];

    if (workflows.isEmpty) {
      if (_wfRetryCount >= 10) {
        _wfRetryCount = 0;
        throw Exception(
          'Workflow not indexed by GitHub yet. '
          'Please wait 1–2 minutes and try again.',
        );
      }
      _wfRetryCount++;
      await Future.delayed(const Duration(seconds: 12));
      return _getWorkflowId(targetRepo);
    }
    _wfRetryCount = 0;

    final wf = workflows.first as Map<String, dynamic>;
    final wfId = wf['id'];
    final wfState = wf['state'] as String?;

    if (wfState != 'active') {
      final htmlUrl =
          wf['html_url']?.toString() ?? 'https://github.com/$targetRepo/actions';
      final actionsUrl = htmlUrl.replaceAll('/blob/master/.github/workflows/build.yml', '/actions');
      throw Exception(
        'Actions disabled. Visit $actionsUrl '
        'and click "I understand my workflows, go ahead and enable them". '
        'Then tap "Build in Cloud" again.',
      );
    }

    return wfId;
  }

  Future<void> dispatchBuild({
    required String appName,
    required String packageName,
    required String platform,
    String? signingKeystoreB64,
    String? keystorePassword,
    String? keyAlias,
    String? keyPassword,
  }) async {
    await _loadToken();
    final username = await getUsername();
    final targetRepo = '$username/mnd-standalone-builder';
    final workflowId = await _getWorkflowId(targetRepo);

    final body = {
      'ref': await getDefaultBranch(),
      'inputs': {
        'app_name': appName,
        'package_name': packageName,
        'platform': platform,
        if (signingKeystoreB64 != null)
          'signing_keystore_b64': signingKeystoreB64,
        if (keystorePassword != null)
          'keystore_password': keystorePassword,
        if (keyAlias != null) 'key_alias': keyAlias,
        if (keyPassword != null) 'key_password': keyPassword,
      },
    };

    final response = await http.post(
      Uri.parse(
        'https://api.github.com/repos/$targetRepo/actions/workflows/$workflowId/dispatches',
      ),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 204) {
      final decoded =
          jsonDecode(response.body) as Map<String, dynamic>?;
      final apiMsg =
          decoded?['message'] as String? ?? response.body;
      throw Exception(
        'Dispatch failed (HTTP ${response.statusCode}): $apiMsg',
      );
    }
  }

  // ─── Polling & Download ────────────────────────────────────────

  Future<String?> pollAndDownload({
    required String appName,
    required void Function(String status, String detail) onProgress,
  }) async {
    await _loadToken();
    final username = await getUsername();
    final targetRepo = '$username/mnd-standalone-builder';

    for (var attempt = 0; attempt < 180; attempt++) {
      await Future.delayed(const Duration(seconds: 10));

      final runsResponse = await http.get(
        Uri.parse(
          'https://api.github.com/repos/$targetRepo/actions/runs?per_page=1',
        ),
        headers: _headers,
      );

      if (runsResponse.statusCode != 200) continue;

      final runsData =
          jsonDecode(runsResponse.body) as Map<String, dynamic>;
      final runs = runsData['workflow_runs'] as List<dynamic>? ?? [];
      if (runs.isEmpty) continue;

      final run = runs.first as Map<String, dynamic>;
      final status = run['status'] as String? ?? '';
      final conclusion = run['conclusion'] as String?;
      final runId = run['id'] as int;

      String? liveStep;
      try {
        final jobsResponse = await http.get(
          Uri.parse(
            'https://api.github.com/repos/$targetRepo/actions/runs/$runId/jobs',
          ),
          headers: _headers,
        );
        if (jobsResponse.statusCode == 200) {
          final jobsData =
              jsonDecode(jobsResponse.body) as Map<String, dynamic>;
          final jobs = jobsData['jobs'] as List<dynamic>? ?? [];
          for (final job in jobs) {
            final steps = job['steps'] as List<dynamic>? ?? [];
            for (final step in steps) {
              final stepStatus = step['status'] as String? ?? '';
              if (stepStatus == 'in_progress') {
                liveStep = step['name'] as String?;
                break;
              }
            }
          }
        }
      } catch (_) {}

      if (status == 'completed') {
        if (conclusion == 'success') {
          final artifactUrl =
              'https://api.github.com/repos/$targetRepo/actions/runs/$runId/artifacts';

          final artResponse = await http.get(
            Uri.parse(artifactUrl),
            headers: _headers,
          );

          if (artResponse.statusCode == 200) {
            final artData =
                jsonDecode(artResponse.body) as Map<String, dynamic>;
            final artifacts =
                artData['artifacts'] as List<dynamic>? ?? [];

            if (artifacts.isNotEmpty) {
              final artifact = artifacts.first as Map<String, dynamic>;
              final downloadUrl =
                  artifact['archive_download_url'] as String?;

              if (downloadUrl != null) {
                onProgress('completed', 'Downloading...');
                final dlResponse = await http.get(
                  Uri.parse(downloadUrl),
                  headers: _headers,
                );
                if (dlResponse.statusCode == 200) {
                  return base64Encode(dlResponse.bodyBytes);
                }
              }
            }
          }
        }

        onProgress(
          'completed',
          conclusion == 'success'
              ? 'Build complete, downloading...'
              : 'Build failed: $conclusion',
        );
        return null;
      }

      final message = liveStep ??
          (status == 'queued'
              ? 'Waiting for build server...'
              : 'Building...');
      onProgress('building', message);
    }

    onProgress('error', 'Build timed out');
    return null;
  }
}
