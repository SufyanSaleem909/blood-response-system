import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String baseUrl = "http://192.168.100.53:8000"; // match main.dart

class HistoryScreen extends StatefulWidget {
  final String token;
  const HistoryScreen({super.key, required this.token});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> myRequests = [];
  List<dynamic> myResponses = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => isLoading = true);
    try {
      final headers = {"Authorization": "Bearer ${widget.token}"};
      final reqRes = await http.get(
        Uri.parse("$baseUrl/blood-requests/mine/requests"),
        headers: headers,
      );
      final respRes = await http.get(
        Uri.parse("$baseUrl/blood-requests/mine/responses"),
        headers: headers,
      );

      setState(() {
        myRequests = reqRes.statusCode == 200 ? jsonDecode(reqRes.body) : [];
        myResponses = respRes.statusCode == 200 ? jsonDecode(respRes.body) : [];
      });
    } catch (_) {
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _markFulfilled(String requestId) async {
    final res = await http.patch(
      Uri.parse("$baseUrl/blood-requests/$requestId/status"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${widget.token}",
      },
      body: jsonEncode({"status": "fulfilled"}),
    );
    if (res.statusCode == 200) {
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Activity"),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: "My Requests"),
            Tab(text: "My Donations"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRequestsList(scheme),
                _buildResponsesList(scheme),
              ],
            ),
    );
  }

  Widget _buildRequestsList(ColorScheme scheme) {
    if (myRequests.isEmpty) {
      return Center(
        child: Text(
          "You haven't posted any requests yet.",
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: myRequests.length,
        itemBuilder: (_, i) {
          final r = myRequests[i];
          final status = r["status"];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primary.withValues(alpha: 0.1),
                child: Text(
                  r["blood_type_needed"],
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              title: Text(
                r["hospital_name"],
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                "${r['units_needed']} unit(s) · ${status.toString().toUpperCase()}",
              ),
              trailing: status == "open"
                  ? TextButton(
                      onPressed: () => _markFulfilled(r["id"]),
                      child: const Text("Mark fulfilled"),
                    )
                  : Icon(
                      status == "fulfilled" ? Icons.check_circle : Icons.cancel,
                      color: status == "fulfilled" ? Colors.green : Colors.grey,
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResponsesList(ColorScheme scheme) {
    if (myResponses.isEmpty) {
      return Center(
        child: Text(
          "You haven't responded to any requests yet.",
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: myResponses.length,
        itemBuilder: (_, i) {
          final r = myResponses[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(
                r["status"] == "accepted" ? Icons.check_circle : Icons.cancel,
                color: r["status"] == "accepted" ? Colors.green : Colors.red,
              ),
              title: Text(
                "Request ${r['request_id'].toString().substring(0, 8)}...",
              ),
              subtitle: Text(r["status"].toString().toUpperCase()),
            ),
          );
        },
      ),
    );
  }
}
