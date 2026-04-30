import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/community_controller.dart';
import '../controllers/auth_controller.dart';
import 'package:http/http.dart' as http;

// ── Helpers ───────────────────────────────────────────────────────────────────

String _timeAgo(int ms) {
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (diff.inDays > 6)  return "${(diff.inDays / 7).floor()}w ago";
  if (diff.inDays > 0)  return "${diff.inDays}d ago";
  if (diff.inHours > 0) return "${diff.inHours}h ago";
  if (diff.inMinutes > 0) return "${diff.inMinutes}m ago";
  return "just now";
}

String _formatDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const months = ["Jan","Feb","Mar","Apr","May","Jun",
                  "Jul","Aug","Sep","Oct","Nov","Dec"];
  const days   = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
  final dow = days[d.weekday - 1];
  final h   = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
  final ampm = d.hour >= 12 ? "PM" : "AM";
  final min  = d.minute.toString().padLeft(2, "0");
  return "$dow ${d.day} ${months[d.month-1]}, $h:$min $ampm";
}

InputDecoration _darkInput(String label, IconData icon) => InputDecoration(
  labelText: label,
  labelStyle: const TextStyle(color: Colors.white38),
  prefixIcon: Icon(icon, color: Colors.white38, size: 20),
  filled: true,
  fillColor: const Color(0xFF1E1E1E),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
  ),
);

// ── CommunityScreen ───────────────────────────────────────────────────────────

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final community = Get.find<CommunityController>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Community',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.redAccent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.dynamic_feed, size: 18), text: 'Feed'),
            Tab(icon: Icon(Icons.group, size: 18), text: 'Groups'),
            Tab(icon: Icon(Icons.motorcycle, size: 18), text: 'Rides'),
            Tab(icon: Icon(Icons.explore, size: 18), text: 'Discover'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 1
          ? FloatingActionButton(
              backgroundColor: Colors.redAccent,
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () => _showCreateGroup(),
            )
          : _tabs.index == 2
              ? FloatingActionButton(
                  backgroundColor: Colors.blueAccent,
                  child: const Icon(Icons.add_road, color: Colors.white),
                  onPressed: () => _showCreateRide(),
                )
              : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          _FeedTab(community: community),
          _GroupsTab(community: community),
          _RidesTab(community: community),
          _DiscoverTab(community: community),
        ],
      ),
    );
  }

  void _showCreateGroup() {
    Get.bottomSheet(
      CreateGroupSheet(community: community),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  void _showCreateRide() {
    if (community.myGroups.isEmpty) {
      Get.snackbar('No Groups', 'Join or create a group first.',
          backgroundColor: Colors.orange, colorText: Colors.white);
      return;
    }
    Get.bottomSheet(
      CreateRideSheet(community: community),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}

// ── Feed Tab ──────────────────────────────────────────────────────────────────

class _FeedTab extends StatefulWidget {
  final CommunityController community;
  const _FeedTab({required this.community});
  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  final _postCtrl = TextEditingController();

  @override
  void dispose() {
    _postCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Post input
      Container(
        color: const Color(0xFF141414),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          Obx(() {
            final auth = Get.find<AuthController>();
            return CircleAvatar(
              radius: 18,
              backgroundColor: auth.avatarColor,
              child: Text(auth.initials,
                  style: const TextStyle(color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.bold)),
            );
          }),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _postCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Share something with your groups...",
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final text = _postCtrl.text.trim();
              if (text.isEmpty) return;
              await widget.community.postToFeed(text);
              _postCtrl.clear();
            },
            child: Container(
              width: 38, height: 38,
              decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
      // Feed list
      Expanded(
        child: Obx(() {
          if (widget.community.loadingFeed.value && widget.community.feedPosts.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
          }
          if (widget.community.feedPosts.isEmpty) {
            return _emptyState(Icons.dynamic_feed,
                'No activity yet', 'Join groups and plan rides to see updates here.');
          }
          return RefreshIndicator(
            color: Colors.redAccent,
            backgroundColor: const Color(0xFF1A1A1A),
            onRefresh: widget.community.fetchFeed,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.community.feedPosts.length,
              itemBuilder: (_, i) {
                final post = widget.community.feedPosts[i];
                return _FeedCard(post: post);
              },
            ),
          );
        }),
      ),
    ]);
  }
}

class _FeedCard extends StatelessWidget {
  final FeedPost post;
  const _FeedCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: post.iconColor.withOpacity(0.2),
          child: Icon(post.icon, color: post.iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(post.authorName,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 6),
              Text(_timeAgo(post.createdAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            Text(post.content,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

// ── Groups Tab ────────────────────────────────────────────────────────────────

class _GroupsTab extends StatelessWidget {
  final CommunityController community;
  const _GroupsTab({required this.community});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (community.loadingGroups.value && community.myGroups.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
      }
      if (community.myGroups.isEmpty) {
        return _emptyState(Icons.group_outlined,
            'No groups yet', 'Create a group or discover existing ones.');
      }
      return RefreshIndicator(
        color: Colors.redAccent,
        backgroundColor: const Color(0xFF1A1A1A),
        onRefresh: community.fetchMyGroups,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: community.myGroups.length,
          itemBuilder: (_, i) => _GroupCard(
            group: community.myGroups[i],
            onTap: () {
              community.activeGroup.value = community.myGroups[i];
              community.fetchGroupRides(community.myGroups[i].id);
              Get.to(() => GroupDetailScreen(group: community.myGroups[i]));
            },
          ),
        ),
      );
    });
  }
}

class _GroupCard extends StatelessWidget {
  final RiderGroup group;
  final VoidCallback onTap;
  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(children: [
          // Banner
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: group.color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: group.color.withOpacity(0.2),
                child: Text(
                  group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                  style: TextStyle(color: group.color,
                      fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(group.name,
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  if (group.description.isNotEmpty)
                    Text(group.description,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: group.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people, color: group.color, size: 13),
                  const SizedBox(width: 4),
                  Text('${group.memberCount}',
                      style: TextStyle(color: group.color,
                          fontWeight: FontWeight.bold, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Rides Tab ─────────────────────────────────────────────────────────────────

class _RidesTab extends StatelessWidget {
  final CommunityController community;
  const _RidesTab({required this.community});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (community.loadingRides.value && community.groupRides.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
      }
      if (community.groupRides.isEmpty) {
        return _emptyState(Icons.motorcycle_outlined,
            'No rides planned', 'Create a ride from a group or tap + below.');
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: community.groupRides.length,
        itemBuilder: (_, i) => _RideCard(
          ride: community.groupRides[i],
          community: community,
        ),
      );
    });
  }
}

class _RideCard extends StatelessWidget {
  final GroupRide ride;
  final CommunityController community;
  const _RideCard({required this.ride, required this.community});

  @override
  Widget build(BuildContext context) {
    final isUpcoming = ride.isUpcoming;
    final statusColor = isUpcoming ? Colors.blueAccent : Colors.white38;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isUpcoming ? Colors.blueAccent.withOpacity(0.3) : Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(ride.status.toUpperCase(),
                style: TextStyle(color: statusColor, fontSize: 10,
                    fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          const Spacer(),
          Text(_timeAgo(ride.createdAt),
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        Text(ride.title,
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        if (ride.startLocation.isNotEmpty || ride.endLocation.isNotEmpty)
          Row(children: [
            const Icon(Icons.location_on, color: Colors.greenAccent, size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                ride.startLocation.isNotEmpty && ride.endLocation.isNotEmpty
                    ? '${ride.startLocation}  →  ${ride.endLocation}'
                    : ride.startLocation.isNotEmpty
                        ? ride.startLocation
                        : ride.endLocation,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.calendar_today, color: Colors.white38, size: 13),
          const SizedBox(width: 4),
          Text(_formatDate(ride.scheduledAt),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const Spacer(),
          const Icon(Icons.people, color: Colors.white38, size: 13),
          const SizedBox(width: 4),
          Text('${ride.participantCount} riders',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text('by ${ride.creatorName}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const Spacer(),
          if (isUpcoming)
            Obx(() => GestureDetector(
              onTap: community.actionLoading.value
                  ? null
                  : () => ride.isJoined
                      ? community.leaveRide(ride.id)
                      : community.joinRide(ride.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: ride.isJoined
                      ? Colors.white12
                      : Colors.blueAccent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ride.isJoined ? 'Leave' : "I'm In!",
                  style: TextStyle(
                    color: ride.isJoined ? Colors.white54 : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            )),
        ]),
      ]),
    );
  }
}

// ── Discover Tab ──────────────────────────────────────────────────────────────

class _DiscoverTab extends StatefulWidget {
  final CommunityController community;
  const _DiscoverTab({required this.community});
  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  @override
  void initState() {
    super.initState();
    widget.community.fetchDiscoverGroups();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (widget.community.discoverGroups.isEmpty) {
        return _emptyState(Icons.explore_outlined,
            'No groups to discover', 'You have joined all available groups!');
      }
      return RefreshIndicator(
        color: Colors.redAccent,
        backgroundColor: const Color(0xFF1A1A1A),
        onRefresh: widget.community.fetchDiscoverGroups,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: widget.community.discoverGroups.length,
          itemBuilder: (_, i) {
            final group = widget.community.discoverGroups[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: group.color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: group.color.withOpacity(0.2),
                      child: Text(
                        group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                        style: TextStyle(color: group.color,
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(group.name,
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        if (group.description.isNotEmpty)
                          Text(group.description,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${group.memberCount} members',
                            style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Obx(() => GestureDetector(
                      onTap: widget.community.actionLoading.value
                          ? null
                          : () => widget.community.joinGroup(group.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: group.color,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Join',
                            style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    )),
                  ]),
                ),
              ]),
            );
          },
        ),
      );
    });
  }
}


// ── Group Detail Screen ───────────────────────────────────────────────────────

class GroupDetailScreen extends StatefulWidget {
  final RiderGroup group;
  const GroupDetailScreen({super.key, required this.group});
  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final community = Get.find<CommunityController>();
  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final auth = Get.find<AuthController>();
    try {
      final res = await http.get(
        Uri.parse("\${AuthController.baseUrl}/groups/\${widget.group.id}/members"),
        headers: {
          'Authorization': 'Bearer \${auth.token}',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (mounted) setState(() => _members = list);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMembers = false);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: const Color(0xFF141414),
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.group.color, widget.group.color.withOpacity(0.4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(widget.group.name,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 24, fontWeight: FontWeight.w800)),
                        if (widget.group.description.isNotEmpty)
                          Text(widget.group.description,
                              style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.people, color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Text("${widget.group.memberCount} members",
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabs,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [Tab(text: "Rides"), Tab(text: "Members")],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            // Rides tab
            Obx(() {
              if (community.loadingRides.value && community.groupRides.isEmpty) {
                return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
              }
              if (community.groupRides.isEmpty) {
                return _emptyState(Icons.motorcycle_outlined, "No rides yet", "Tap + to plan the first ride!");
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: community.groupRides.length,
                itemBuilder: (_, i) => _RideCard(ride: community.groupRides[i], community: community),
              );
            }),
            // Members tab
            _loadingMembers
                ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                : _members.isEmpty
                    ? _emptyState(Icons.person_outline, "No members loaded", "")
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _members.length,
                        itemBuilder: (_, i) {
                          final m = _members[i];
                          final isAdmin = m["role"] == "admin";
                          final name = m["name"] as String? ?? "Rider";
                          final parts = name.trim().split(" ");
                          final initials = parts.take(2).map((p) => p.isNotEmpty ? p[0].toUpperCase() : "").join();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: widget.group.color.withOpacity(0.2),
                                child: Text(initials,
                                    style: TextStyle(color: widget.group.color, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  if (m["blood_group"] != null)
                                    Text(m["blood_group"] as String,
                                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ]),
                              ),
                              if (isAdmin)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text("ADMIN",
                                      style: TextStyle(color: Colors.redAccent,
                                          fontSize: 10, fontWeight: FontWeight.w800)),
                                ),
                            ]),
                          );
                        },
                      ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add_road, color: Colors.white),
        onPressed: () => Get.bottomSheet(
          CreateRideSheet(community: community, preselectedGroupId: widget.group.id),
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}

// ── Create Group Sheet ────────────────────────────────────────────────────────

class CreateGroupSheet extends StatefulWidget {
  final CommunityController community;
  const CreateGroupSheet({super.key, required this.community});
  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _selectedColor = '#E91E63';

  static const _colors = [
    '#E91E63', '#2196F3', '#4CAF50',
    '#FF9800', '#9C27B0', '#009688',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.white24,
                borderRadius: BorderRadius.circular(2))),
        const Text("Create a Group",
            style: TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _darkInput("Group Name", Icons.group),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _descCtrl,
          style: const TextStyle(color: Colors.white),
          maxLines: 2,
          decoration: _darkInput("Description (optional)", Icons.description),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text("Banner Color",
              style: TextStyle(color: Colors.white54, fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _colors.map((hex) {
            final color = Color(int.parse("FF${hex.replaceAll('#', '')}", radix: 16));
            final selected = _selectedColor == hex;
            return GestureDetector(
              onTap: () => setState(() => _selectedColor = hex),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Obx(() => SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: widget.community.actionLoading.value
                ? null
                : () async {
                    if (_nameCtrl.text.trim().isEmpty) return;
                    final ok = await widget.community.createGroup(
                      name: _nameCtrl.text.trim(),
                      description: _descCtrl.text.trim(),
                      bannerColor: _selectedColor,
                    );
                    if (ok) {
                      Get.back();
                      Get.snackbar("Group Created!", _nameCtrl.text.trim(),
                          backgroundColor: Colors.green, colorText: Colors.white);
                    }
                  },
            child: widget.community.actionLoading.value
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Create Group",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        )),
      ]),
    );
  }
}

// ── Create Ride Sheet ─────────────────────────────────────────────────────────

class CreateRideSheet extends StatefulWidget {
  final CommunityController community;
  final int? preselectedGroupId;
  final String? prefillTitle;
  final String? prefillDesc;
  const CreateRideSheet({
    super.key,
    required this.community,
    this.preselectedGroupId,
    this.prefillTitle,
    this.prefillDesc,
  });
  @override
  State<CreateRideSheet> createState() => _CreateRideSheetState();
}

class _CreateRideSheetState extends State<CreateRideSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _startCtrl = TextEditingController();
  final _endCtrl   = TextEditingController();
  DateTime _scheduledAt = DateTime.now().add(const Duration(days: 1));
  int? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.preselectedGroupId ??
        (widget.community.myGroups.isNotEmpty
            ? widget.community.myGroups.first.id
            : null);
    // Pre-fill from trip share
    if (widget.prefillTitle != null) _titleCtrl.text = widget.prefillTitle!;
    if (widget.prefillDesc  != null) _descCtrl.text  = widget.prefillDesc!;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.redAccent),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.redAccent),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.of(context).viewInsets.bottom + 32),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const Text("Plan a Ride",
              style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          // Group selector
          if (widget.preselectedGroupId == null)
            Obx(() => DropdownButtonFormField<int>(
              value: _selectedGroupId,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
              decoration: _darkInput("Select Group", Icons.group),
              items: widget.community.myGroups.map((g) =>
                DropdownMenuItem(value: g.id,
                    child: Text(g.name, style: const TextStyle(color: Colors.white)))
              ).toList(),
              onChanged: (v) => setState(() => _selectedGroupId = v),
            )),
          if (widget.preselectedGroupId == null) const SizedBox(height: 14),
          TextField(controller: _titleCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _darkInput("Ride Title", Icons.motorcycle)),
          const SizedBox(height: 14),
          TextField(controller: _descCtrl,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: _darkInput("Description (optional)", Icons.description)),
          const SizedBox(height: 14),
          TextField(controller: _startCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _darkInput("Start Location", Icons.location_on)),
          const SizedBox(height: 14),
          TextField(controller: _endCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: _darkInput("End Location", Icons.flag)),
          const SizedBox(height: 14),
          // Date/time picker
          GestureDetector(
            onTap: _pickDateTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today, color: Colors.white38, size: 20),
                const SizedBox(width: 12),
                Text(_formatDate(_scheduledAt.millisecondsSinceEpoch),
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const Spacer(),
                const Icon(Icons.edit, color: Colors.white38, size: 16),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          Obx(() => SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: widget.community.actionLoading.value || _selectedGroupId == null
                  ? null
                  : () async {
                      if (_titleCtrl.text.trim().isEmpty) return;
                      final ok = await widget.community.createRide(
                        groupId: _selectedGroupId!,
                        title: _titleCtrl.text.trim(),
                        description: _descCtrl.text.trim(),
                        startLocation: _startCtrl.text.trim(),
                        endLocation: _endCtrl.text.trim(),
                        scheduledAt: _scheduledAt,
                      );
                      if (ok) {
                        Get.back();
                        Get.snackbar("Ride Created!", _titleCtrl.text.trim(),
                            backgroundColor: Colors.blueAccent, colorText: Colors.white);
                      }
                    },
              child: widget.community.actionLoading.value
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Create Ride",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          )),
        ]),
      ),
    );
  }
}

// ── Shared empty state ────────────────────────────────────────────────────────

Widget _emptyState(IconData icon, String title, String subtitle) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 64, color: Colors.white12),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(color: Colors.white38, fontSize: 18,
                fontWeight: FontWeight.w600)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(color: Colors.white24, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ]),
    ),
  );
}
