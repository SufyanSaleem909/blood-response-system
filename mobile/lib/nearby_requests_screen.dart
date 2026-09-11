import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String baseUrl = "http://192.168.100.53:8000"; // match main.dart

class NearbyRequestsScreen extends StatefulWidget {
  final String token;
  final String donorId;
  const NearbyRequestsScreen({
    super.key,
    required this.token,
    required this.donorId,
  });

  @override
  State<NearbyRequestsScreen> createState() => _NearbyRequestsScreenState();
}

class _NearbyRequestsScreenState extends State<NearbyRequestsScreen> {
  List<dynamic> requests = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/blood-requests/nearby/for-donor"),
        headers: {"Authorization": "Bearer ${widget.token}"},
      );
      if (res.statusCode == 200) {
        setState(() => requests = jsonDecode(res.body)["requests"] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _respond(String requestId, String status) async {
    final res = await http.post(
      Uri.parse("$baseUrl/blood-requests/$requestId/respond"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      },
      body: jsonEncode({"donor_id": widget.donorId, "status": status}),
    );
    if (res.statusCode == 201) {
      _load();
      if (mounted) {
        if (status == "accepted") {
          _promptStatusMessage(requestId);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Response recorded: $status")));
        }
      }
    }
  }

  Future<void> _promptStatusMessage(String requestId) async {
    final controller = TextEditingController(text: "On my way, ETA 20 minutes");
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Let them know you're coming"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "e.g. On my way, ETA 20 minutes",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Skip"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Send"),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final patchRes = await http.patch(
        Uri.parse("$baseUrl/blood-requests/$requestId/respond/status-message"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${widget.token}",
        },
        body: jsonEncode({"status_message": result}),
      );

      if (mounted && patchRes.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Status sent to requester.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Nearby Open Requests")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : requests.isEmpty
          ? Center(
              child: Text(
                "No open requests near you right now.",
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                itemBuilder: (_, i) {
                  final r = requests[i];
                  final alreadyResponded = r["already_responded"] == true;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: scheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: Text(
                              r["blood_type_needed"],
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r["hospital_name"],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  "${r['units_needed']} unit(s) · ${r['distance_km']} km away",
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (alreadyResponded)
                            const Chip(
                              label: Text(
                                "Responded",
                                style: TextStyle(fontSize: 10),
                              ),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                                  onPressed: () =>
                                      _respond(r["id"], "accepted"),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.cancel,
                                    color: Colors.red,
                                  ),
                                  onPressed: () =>
                                      _respond(r["id"], "declined"),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
