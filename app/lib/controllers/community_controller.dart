import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'auth_controller.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class RiderGroup {
  final int id;
  final String name;
  final String description;
  final String bannerColor;
  final int creatorId;
  final int createdAt;
  final int memberCount;
  final bool isMember;

  RiderGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.bannerColor,
    required this.creatorId,
    required this.createdAt,
    required this.memberCount,
    required this.isMember,
  });

  factory RiderGroup.fromJson(Map<String, dynamic> j) => RiderGroup(
        id: j['id'] as int,
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        bannerColor: j['banner_color'] as String? ?? '#E91E63',
        creatorId: j['creator_id'] as int,
        createdAt: j['created_at'] as int,
        memberCount: j['member_count'] as int? ?? 0,
        isMember: (j['is_member'] as int? ?? 0) == 1 || j['is_member'] == true,
      );

  Color get color {
    try {
      final hex = bannerColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.pink;
    }
  }
}

class GroupRide {
  final int id;
  final int groupId;
  final int creatorId;
  final String creatorName;
  final String title;
  final String description;
  final String startLocation;
  final String endLocation;
  final double? startLat;
  final double? startLng;
  final double? endLat;
  final double? endLng;
  final int scheduledAt;
  final String status;
  final int createdAt;
  final int participantCount;
  final bool isJoined;

  GroupRide({
    required this.id,
    required this.groupId,
    required this.creatorId,
    required this.creatorName,
    required this.title,
    required this.description,
    required this.startLocation,
    required this.endLocation,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    required this.scheduledAt,
    required this.status,
    required this.createdAt,
    required this.participantCount,
    required this.isJoined,
  });

  factory GroupRide.fromJson(Map<String, dynamic> j) => GroupRide(
        id: j['id'] as int,
        groupId: j['group_id'] as int,
        creatorId: j['creator_id'] as int,
        creatorName: j['creator_name'] as String? ?? 'Rider',
        title: j['title'] as String,
        description: j['description'] as String? ?? '',
        startLocation: j['start_location'] as String? ?? '',
        endLocation: j['end_location'] as String? ?? '',
        startLat: (j['start_lat'] as num?)?.toDouble(),
        startLng: (j['start_lng'] as num?)?.toDouble(),
        endLat: (j['end_lat'] as num?)?.toDouble(),
        endLng: (j['end_lng'] as num?)?.toDouble(),
        scheduledAt: j['scheduled_at'] as int,
        status: j['status'] as String? ?? 'upcoming',
        createdAt: j['created_at'] as int,
        participantCount: j['participant_count'] as int? ?? 0,
        isJoined: (j['is_joined'] as int? ?? 0) > 0,
      );

  DateTime get scheduledDate =>
      DateTime.fromMillisecondsSinceEpoch(scheduledAt);

  bool get isUpcoming =>
      scheduledDate.isAfter(DateTime.now()) && status == 'upcoming';
}

class FeedPost {
  final int id;
  final int userId;
  final int? groupId;
  final String postType;
  final String content;
  final int createdAt;
  final String authorName;
  final String authorInitials;

  FeedPost({
    required this.id,
    required this.userId,
    this.groupId,
    required this.postType,
    required this.content,
    required this.createdAt,
    required this.authorName,
    required this.authorInitials,
  });

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        id: j['id'] as int,
        userId: j['user_id'] as int,
        groupId: j['group_id'] as int?,
        postType: j['post_type'] as String? ?? 'update',
        content: j['content'] as String,
        createdAt: j['created_at'] as int,
        authorName: j['author_name'] as String? ?? 'Rider',
        authorInitials: j['author_initials'] as String? ?? '?',
      );

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(createdAt);

  IconData get icon {
    switch (postType) {
      case 'ride_created': return Icons.motorcycle;
      case 'ride_joined':  return Icons.group_add;
      case 'joined':       return Icons.person_add;
      default:             return Icons.chat_bubble_outline;
    }
  }

  Color get iconColor {
    switch (postType) {
      case 'ride_created': return Colors.redAccent;
      case 'ride_joined':  return Colors.blueAccent;
      case 'joined':       return Colors.greenAccent;
      default:             return Colors.white54;
    }
  }
}

// ── Controller ────────────────────────────────────────────────────────────────

class CommunityController extends GetxController {
  final _auth = Get.find<AuthController>();

  String get _base => AuthController.baseUrl;
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_auth.token}',
      };

  // ── Reactive state ──────────────────────────────────────────────────────────
  final RxList<RiderGroup> myGroups      = <RiderGroup>[].obs;
  final RxList<RiderGroup> discoverGroups = <RiderGroup>[].obs;
  final RxList<GroupRide>  groupRides    = <GroupRide>[].obs;
  final RxList<FeedPost>   feedPosts     = <FeedPost>[].obs;

  final RxBool loadingGroups  = false.obs;
  final RxBool loadingRides   = false.obs;
  final RxBool loadingFeed    = false.obs;
  final RxBool actionLoading  = false.obs;
  final RxString errorMsg     = ''.obs;

  // Currently viewed group (for detail screen)
  final Rx<RiderGroup?> activeGroup = Rx<RiderGroup?>(null);

  @override
  void onInit() {
    super.onInit();
    fetchMyGroups();
    fetchFeed();
  }

  // ── Groups ──────────────────────────────────────────────────────────────────

  Future<void> fetchMyGroups() async {
    loadingGroups.value = true;
    try {
      final res = await http
          .get(Uri.parse('$_base/groups'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        myGroups.assignAll(list.map((j) => RiderGroup.fromJson(j)));
      }
    } catch (_) {} finally {
      loadingGroups.value = false;
    }
  }

  Future<void> fetchDiscoverGroups() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/groups/discover'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        discoverGroups.assignAll(list.map((j) => RiderGroup.fromJson(j)));
      }
    } catch (_) {}
  }

  Future<bool> createGroup({
    required String name,
    required String description,
    required String bannerColor,
  }) async {
    actionLoading.value = true;
    errorMsg.value = '';
    try {
      final res = await http
          .post(
            Uri.parse('$_base/groups'),
            headers: _headers,
            body: jsonEncode({
              'name': name,
              'description': description,
              'banner_color': bannerColor,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 201) {
        final g = RiderGroup.fromJson(jsonDecode(res.body));
        myGroups.insert(0, g);
        return true;
      }
      errorMsg.value = (jsonDecode(res.body)['detail'] ?? 'Failed').toString();
      return false;
    } catch (_) {
      errorMsg.value = 'Network error';
      return false;
    } finally {
      actionLoading.value = false;
    }
  }

  Future<void> joinGroup(int groupId) async {
    actionLoading.value = true;
    try {
      final res = await http
          .post(Uri.parse('$_base/groups/$groupId/join'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        // Move from discover → myGroups
        final idx = discoverGroups.indexWhere((g) => g.id == groupId);
        if (idx != -1) {
          final g = discoverGroups[idx];
          discoverGroups.removeAt(idx);
          myGroups.insert(0, RiderGroup(
            id: g.id, name: g.name, description: g.description,
            bannerColor: g.bannerColor, creatorId: g.creatorId,
            createdAt: g.createdAt,
            memberCount: g.memberCount + 1, isMember: true,
          ));
        }
        fetchFeed();
        Get.snackbar('Joined!', 'You joined the group.',
            backgroundColor: Colors.green, colorText: Colors.white);
      }
    } catch (_) {} finally {
      actionLoading.value = false;
    }
  }

  Future<void> leaveGroup(int groupId) async {
    await http
        .delete(Uri.parse('$_base/groups/$groupId/leave'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    myGroups.removeWhere((g) => g.id == groupId);
    if (activeGroup.value?.id == groupId) activeGroup.value = null;
  }

  // ── Rides ───────────────────────────────────────────────────────────────────

  Future<void> fetchGroupRides(int groupId) async {
    loadingRides.value = true;
    try {
      final res = await http
          .get(Uri.parse('$_base/groups/$groupId/rides'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        groupRides.assignAll(list.map((j) => GroupRide.fromJson(j)));
      }
    } catch (_) {} finally {
      loadingRides.value = false;
    }
  }

  Future<bool> createRide({
    required int groupId,
    required String title,
    required String description,
    required String startLocation,
    required String endLocation,
    required DateTime scheduledAt,
  }) async {
    actionLoading.value = true;
    errorMsg.value = '';
    try {
      final res = await http
          .post(
            Uri.parse('$_base/rides'),
            headers: _headers,
            body: jsonEncode({
              'group_id': groupId,
              'title': title,
              'description': description,
              'start_location': startLocation,
              'end_location': endLocation,
              'scheduled_at': scheduledAt.millisecondsSinceEpoch,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 201) {
        final r = GroupRide.fromJson(jsonDecode(res.body));
        groupRides.insert(0, r);
        fetchFeed();
        return true;
      }
      errorMsg.value = (jsonDecode(res.body)['detail'] ?? 'Failed').toString();
      return false;
    } catch (_) {
      errorMsg.value = 'Network error';
      return false;
    } finally {
      actionLoading.value = false;
    }
  }

  Future<void> joinRide(int rideId) async {
    actionLoading.value = true;
    try {
      final res = await http
          .post(Uri.parse('$_base/rides/$rideId/join'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final idx = groupRides.indexWhere((r) => r.id == rideId);
        if (idx != -1) {
          final old = groupRides[idx];
          groupRides[idx] = GroupRide(
            id: old.id, groupId: old.groupId, creatorId: old.creatorId,
            creatorName: old.creatorName, title: old.title,
            description: old.description, startLocation: old.startLocation,
            endLocation: old.endLocation, startLat: old.startLat,
            startLng: old.startLng, endLat: old.endLat, endLng: old.endLng,
            scheduledAt: old.scheduledAt, status: old.status,
            createdAt: old.createdAt,
            participantCount: old.participantCount + 1, isJoined: true,
          );
        }
        fetchFeed();
        Get.snackbar("You're in!", 'Ride added to your schedule.',
            backgroundColor: Colors.blueAccent, colorText: Colors.white);
      }
    } catch (_) {} finally {
      actionLoading.value = false;
    }
  }

  Future<void> leaveRide(int rideId) async {
    await http
        .delete(Uri.parse('$_base/rides/$rideId/leave'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final idx = groupRides.indexWhere((r) => r.id == rideId);
    if (idx != -1) {
      final old = groupRides[idx];
      groupRides[idx] = GroupRide(
        id: old.id, groupId: old.groupId, creatorId: old.creatorId,
        creatorName: old.creatorName, title: old.title,
        description: old.description, startLocation: old.startLocation,
        endLocation: old.endLocation, startLat: old.startLat,
        startLng: old.startLng, endLat: old.endLat, endLng: old.endLng,
        scheduledAt: old.scheduledAt, status: old.status,
        createdAt: old.createdAt,
        participantCount: (old.participantCount - 1).clamp(0, 9999),
        isJoined: false,
      );
    }
  }

  // ── Feed ────────────────────────────────────────────────────────────────────

  Future<void> fetchFeed() async {
    loadingFeed.value = true;
    try {
      final res = await http
          .get(Uri.parse('$_base/feed'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        feedPosts.assignAll(list.map((j) => FeedPost.fromJson(j)));
      }
    } catch (_) {} finally {
      loadingFeed.value = false;
    }
  }

  Future<void> postToFeed(String content, {int? groupId}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/feed'),
            headers: _headers,
            body: jsonEncode({
              'content': content,
              if (groupId != null) 'group_id': groupId,
              'post_type': 'update',
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 201) {
        final post = FeedPost.fromJson(jsonDecode(res.body));
        feedPosts.insert(0, post);
      }
    } catch (_) {}
  }
}
