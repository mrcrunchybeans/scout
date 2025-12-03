// lib/features/feedback/feedback_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:scout/utils/operator_store.dart';

/// Types of feedback submissions
enum FeedbackType {
  bug,
  feature,
  question,
}

/// Status of a feedback item
enum FeedbackStatus {
  open,
  inProgress,
  resolved,
  wontFix,
  planned,
}

extension FeedbackTypeExtension on FeedbackType {
  String get label => switch (this) {
    FeedbackType.bug => 'Bug',
    FeedbackType.feature => 'Feature Request',
    FeedbackType.question => 'Question',
  };
  
  IconData get icon => switch (this) {
    FeedbackType.bug => Icons.bug_report,
    FeedbackType.feature => Icons.lightbulb_outline,
    FeedbackType.question => Icons.help_outline,
  };
  
  Color color(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return switch (this) {
      FeedbackType.bug => brightness == Brightness.dark ? Colors.red.shade300 : Colors.red.shade700,
      FeedbackType.feature => brightness == Brightness.dark ? Colors.amber.shade300 : Colors.amber.shade800,
      FeedbackType.question => brightness == Brightness.dark ? Colors.blue.shade300 : Colors.blue.shade700,
    };
  }
}

extension FeedbackStatusExtension on FeedbackStatus {
  String get label => switch (this) {
    FeedbackStatus.open => 'Open',
    FeedbackStatus.inProgress => 'In Progress',
    FeedbackStatus.resolved => 'Resolved',
    FeedbackStatus.wontFix => "Won't Fix",
    FeedbackStatus.planned => 'Planned',
  };
  
  Color color(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return switch (this) {
      FeedbackStatus.open => brightness == Brightness.dark ? Colors.grey.shade400 : Colors.grey.shade700,
      FeedbackStatus.inProgress => brightness == Brightness.dark ? Colors.blue.shade300 : Colors.blue.shade700,
      FeedbackStatus.resolved => brightness == Brightness.dark ? Colors.green.shade300 : Colors.green.shade700,
      FeedbackStatus.wontFix => brightness == Brightness.dark ? Colors.red.shade300 : Colors.red.shade700,
      FeedbackStatus.planned => brightness == Brightness.dark ? Colors.purple.shade300 : Colors.purple.shade700,
    };
  }
  
  IconData get icon => switch (this) {
    FeedbackStatus.open => Icons.radio_button_unchecked,
    FeedbackStatus.inProgress => Icons.pending,
    FeedbackStatus.resolved => Icons.check_circle,
    FeedbackStatus.wontFix => Icons.cancel,
    FeedbackStatus.planned => Icons.schedule,
  };
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  FeedbackType? _filterType;
  FeedbackStatus? _filterStatus;
  bool _showResolved = false;
  String _sortBy = 'votes'; // 'votes', 'recent', 'oldest'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
          tooltip: 'Back to Dashboard',
        ),
        title: const Text('Feedback & Bugs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'All Feedback'),
            Tab(icon: Icon(Icons.add_circle_outline), text: 'Submit New'),
          ],
        ),
        actions: [
          // Filter menu
          PopupMenuButton<String>(
            icon: Badge(
              isLabelVisible: _filterType != null || _filterStatus != null || _showResolved,
              child: const Icon(Icons.filter_list),
            ),
            onSelected: (value) {
              setState(() {
                if (value == 'clear') {
                  _filterType = null;
                  _filterStatus = null;
                  _showResolved = false;
                } else if (value == 'show-resolved') {
                  _showResolved = !_showResolved;
                } else if (value.startsWith('type:')) {
                  final typeStr = value.substring(5);
                  _filterType = _filterType?.name == typeStr ? null : FeedbackType.values.firstWhere((t) => t.name == typeStr);
                } else if (value.startsWith('status:')) {
                  final statusStr = value.substring(7);
                  _filterStatus = _filterStatus?.name == statusStr ? null : FeedbackStatus.values.firstWhere((s) => s.name == statusStr);
                }
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear Filters')),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 'show-resolved',
                checked: _showResolved,
                child: const Text('Show Resolved'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('Filter by Type')),
              ...FeedbackType.values.map((type) => CheckedPopupMenuItem(
                value: 'type:${type.name}',
                checked: _filterType == type,
                child: Row(
                  children: [
                    Icon(type.icon, color: type.color(context), size: 18),
                    const SizedBox(width: 8),
                    Text(type.label),
                  ],
                ),
              )),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('Filter by Status')),
              ...FeedbackStatus.values.where((s) => s != FeedbackStatus.resolved || _showResolved).map((status) => CheckedPopupMenuItem(
                value: 'status:${status.name}',
                checked: _filterStatus == status,
                child: Row(
                  children: [
                    Icon(status.icon, color: status.color(context), size: 18),
                    const SizedBox(width: 8),
                    Text(status.label),
                  ],
                ),
              )),
            ],
          ),
          // Sort menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'votes',
                checked: _sortBy == 'votes',
                child: const Text('Most Voted'),
              ),
              CheckedPopupMenuItem(
                value: 'recent',
                checked: _sortBy == 'recent',
                child: const Text('Most Recent'),
              ),
              CheckedPopupMenuItem(
                value: 'oldest',
                checked: _sortBy == 'oldest',
                child: const Text('Oldest First'),
              ),
            ],
          ),
          // RSS feed button
          IconButton(
            icon: const Icon(Icons.rss_feed),
            tooltip: 'Copy RSS Feed URL',
            onPressed: () {
              const rssUrl = 'https://us-central1-scout-litteempathy.cloudfunctions.net/feedbackRss';
              Clipboard.setData(const ClipboardData(text: rssUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('RSS feed URL copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeedbackList(),
          _SubmitFeedbackForm(onSubmitted: () {
            _tabController.animateTo(0);
          }),
        ],
      ),
    );
  }

  Widget _buildFeedbackList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildQuery().snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snapshot.data!.docs;
        
        // Client-side filtering for resolved items
        if (!_showResolved) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? 'open';
            return status != 'resolved' && status != 'wontFix';
          }).toList();
        }
        
        // Apply type filter
        if (_filterType != null) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['type'] == _filterType!.name;
          }).toList();
        }
        
        // Apply status filter
        if (_filterStatus != null) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['status'] == _filterStatus!.name;
          }).toList();
        }
        
        // Client-side sorting
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          
          switch (_sortBy) {
            case 'votes':
              final aVotes = (aData['voteCount'] ?? 0) as int;
              final bVotes = (bData['voteCount'] ?? 0) as int;
              return bVotes.compareTo(aVotes);
            case 'recent':
              final aTime = aData['createdAt'] as Timestamp?;
              final bTime = bData['createdAt'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            case 'oldest':
              final aTime = aData['createdAt'] as Timestamp?;
              final bTime = bData['createdAt'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return aTime.compareTo(bTime);
            default:
              return 0;
          }
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.feedback_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 16),
                Text(
                  _filterType != null || _filterStatus != null
                      ? 'No matching feedback found'
                      : 'No feedback yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Be the first to submit feedback!',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _tabController.animateTo(1),
                  icon: const Icon(Icons.add),
                  label: const Text('Submit Feedback'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _FeedbackCard(
              id: doc.id,
              data: data,
              onTap: () => _showFeedbackDetail(doc.id, data),
            );
          },
        );
      },
    );
  }

  Query<Map<String, dynamic>> _buildQuery() {
    // Always fetch all and sort client-side to avoid index issues
    return FirebaseFirestore.instance
        .collection('feedback')
        .orderBy('createdAt', descending: true)
        .limit(200);
  }

  void _showFeedbackDetail(String id, Map<String, dynamic> data) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FeedbackDetailPage(id: id, initialData: data),
      ),
    );
  }
}

/// Card widget for displaying a feedback item in the list
class _FeedbackCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _FeedbackCard({
    required this.id,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = FeedbackType.values.firstWhere(
      (t) => t.name == data['type'],
      orElse: () => FeedbackType.bug,
    );
    final status = FeedbackStatus.values.firstWhere(
      (s) => s.name == data['status'],
      orElse: () => FeedbackStatus.open,
    );
    final title = data['title'] as String? ?? 'Untitled';
    final submittedBy = data['submittedBy'] as String? ?? 'Anonymous';
    final voteCount = data['voteCount'] as int? ?? 0;
    final commentCount = data['commentCount'] as int? ?? 0;
    final createdAt = data['createdAt'] as Timestamp?;
    final voters = (data['voters'] as List<dynamic>?)?.cast<String>() ?? [];
    
    // Check if current user has voted
    final currentUser = OperatorStore.name.value ?? '';
    final hasVoted = voters.contains(currentUser);
    
    final typeColor = type.color(context);
    final statusColor = status.color(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vote button
              _VoteButton(
                id: id,
                voteCount: voteCount,
                hasVoted: hasVoted,
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type and status badges
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(type.icon, size: 14, color: typeColor),
                              const SizedBox(width: 4),
                              Text(
                                type.label,
                                style: TextStyle(fontSize: 11, color: typeColor, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(status.icon, size: 14, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                status.label,
                                style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Title
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: status == FeedbackStatus.resolved ? TextDecoration.lineThrough : null,
                        color: status == FeedbackStatus.resolved ? cs.outline : cs.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Meta info
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          submittedBy,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        if (createdAt != null) ...[
                          Icon(Icons.access_time, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(createdAt.toDate()),
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                        const Spacer(),
                        if (commentCount > 0) ...[
                          Icon(Icons.comment_outlined, size: 14, color: cs.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '$commentCount',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(date);
    }
  }
}

/// Vote button with animation
class _VoteButton extends StatelessWidget {
  final String id;
  final int voteCount;
  final bool hasVoted;

  const _VoteButton({
    required this.id,
    required this.voteCount,
    required this.hasVoted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: () => _toggleVote(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: hasVoted ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasVoted ? cs.primary : cs.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasVoted ? Icons.thumb_up : Icons.thumb_up_outlined,
              size: 20,
              color: hasVoted ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              '$voteCount',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: hasVoted ? cs.primary : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleVote(BuildContext context) async {
    final currentUser = OperatorStore.name.value;
    if (currentUser == null || currentUser.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set your name first (tap your name in the header)')),
      );
      return;
    }

    final ref = FirebaseFirestore.instance.collection('feedback').doc(id);
    
    if (hasVoted) {
      // Remove vote
      await ref.update({
        'voters': FieldValue.arrayRemove([currentUser]),
        'voteCount': FieldValue.increment(-1),
      });
    } else {
      // Add vote
      await ref.update({
        'voters': FieldValue.arrayUnion([currentUser]),
        'voteCount': FieldValue.increment(1),
      });
    }
  }
}

/// Form for submitting new feedback
class _SubmitFeedbackForm extends StatefulWidget {
  final VoidCallback onSubmitted;

  const _SubmitFeedbackForm({required this.onSubmitted});

  @override
  State<_SubmitFeedbackForm> createState() => _SubmitFeedbackFormState();
}

class _SubmitFeedbackFormState extends State<_SubmitFeedbackForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  FeedbackType _selectedType = FeedbackType.bug;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentUser = OperatorStore.name.value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User name prompt if not set
            if (currentUser == null || currentUser.isEmpty)
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: cs.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Please set your name first by tapping the badge in the app header.',
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Type selection
            Text('What type of feedback?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: FeedbackType.values.map((type) {
                final isSelected = _selectedType == type;
                final typeColor = type.color(context);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: type != FeedbackType.question ? 8 : 0),
                    child: InkWell(
                      onTap: () => setState(() => _selectedType = type),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: isSelected ? typeColor.withValues(alpha: 0.15) : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? typeColor : cs.outline.withValues(alpha: 0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(type.icon, color: isSelected ? typeColor : cs.onSurfaceVariant, size: 28),
                            const SizedBox(height: 4),
                            Text(
                              type.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? typeColor : cs.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: _selectedType == FeedbackType.bug
                    ? 'What went wrong?'
                    : _selectedType == FeedbackType.feature
                        ? 'What would you like to see?'
                        : 'What\'s your question?',
                hintText: _selectedType == FeedbackType.bug
                    ? 'e.g., Items disappear when scanning barcode'
                    : _selectedType == FeedbackType.feature
                        ? 'e.g., Add dark mode support'
                        : 'e.g., How do I export inventory?',
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Details (optional)',
                hintText: _selectedType == FeedbackType.bug
                    ? 'Steps to reproduce, what you expected to happen...'
                    : 'Any additional details or context...',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
              textInputAction: TextInputAction.newline,
            ),

            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (currentUser == null || currentUser.isEmpty || _submitting) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Submitting...' : 'Submit Feedback'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final currentUser = OperatorStore.name.value ?? 'Anonymous';
      
      await FirebaseFirestore.instance.collection('feedback').add({
        'type': _selectedType.name,
        'status': FeedbackStatus.open.name,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'submittedBy': currentUser,
        'voteCount': 1, // Auto-vote for your own submission
        'voters': [currentUser],
        'commentCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feedback submitted! Thank you.'),
          backgroundColor: Colors.green,
        ),
      );

      _titleController.clear();
      _descriptionController.clear();
      setState(() => _selectedType = FeedbackType.bug);
      
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// Detail page for viewing and managing a single feedback item
class _FeedbackDetailPage extends StatefulWidget {
  final String id;
  final Map<String, dynamic> initialData;

  const _FeedbackDetailPage({required this.id, required this.initialData});

  @override
  State<_FeedbackDetailPage> createState() => _FeedbackDetailPageState();
}

class _FeedbackDetailPageState extends State<_FeedbackDetailPage> {
  final _commentController = TextEditingController();
  bool _isAdmin = false;
  bool _submittingComment = false;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  void _checkAdmin() {
    // Simple admin check - you can customize this
    final currentUser = OperatorStore.name.value?.toLowerCase() ?? '';
    _isAdmin = currentUser == 'brian' || currentUser.contains('admin');
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('feedback').doc(widget.id).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? widget.initialData;
        
        final type = FeedbackType.values.firstWhere(
          (t) => t.name == data['type'],
          orElse: () => FeedbackType.bug,
        );
        final status = FeedbackStatus.values.firstWhere(
          (s) => s.name == data['status'],
          orElse: () => FeedbackStatus.open,
        );
        final title = data['title'] as String? ?? 'Untitled';
        final description = data['description'] as String? ?? '';
        final submittedBy = data['submittedBy'] as String? ?? 'Anonymous';
        final voteCount = data['voteCount'] as int? ?? 0;
        final createdAt = data['createdAt'] as Timestamp?;
        final voters = (data['voters'] as List<dynamic>?)?.cast<String>() ?? [];
        final currentUser = OperatorStore.name.value ?? '';
        final hasVoted = voters.contains(currentUser);
        
        final typeColor = type.color(context);
        final statusColor = status.color(context);

        return Scaffold(
          appBar: AppBar(
            title: Text(type.label),
            actions: [
              if (_isAdmin)
                PopupMenuButton<FeedbackStatus>(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Change Status',
                  onSelected: (newStatus) => _updateStatus(newStatus),
                  itemBuilder: (context) => FeedbackStatus.values.map((s) => PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Icon(s.icon, color: s.color(context), size: 18),
                        const SizedBox(width: 8),
                        Text(s.label),
                        if (s == status) ...[
                          const Spacer(),
                          const Icon(Icons.check, size: 18),
                        ],
                      ],
                    ),
                  )).toList(),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with type and status
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(type.icon, size: 16, color: typeColor),
                                const SizedBox(width: 6),
                                Text(
                                  type.label,
                                  style: TextStyle(color: typeColor, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(status.icon, size: 16, color: statusColor),
                                const SizedBox(width: 6),
                                Text(
                                  status.label,
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _VoteButton(id: widget.id, voteCount: voteCount, hasVoted: hasVoted),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Title
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Meta info
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: cs.primaryContainer,
                            child: Text(
                              submittedBy.isNotEmpty ? submittedBy[0].toUpperCase() : '?',
                              style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(submittedBy, style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(width: 8),
                          Text('•', style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(width: 8),
                          if (createdAt != null)
                            Text(
                              DateFormat('MMM d, yyyy • h:mm a').format(createdAt.toDate()),
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                      
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        Text(
                          description,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      
                      // Comments section
                      Text(
                        'Responses & Updates',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildCommentsList(),
                    ],
                  ),
                ),
              ),
              
              // Comment input
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: _isAdmin ? 'Add a response...' : 'Add a comment...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            isDense: true,
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitComment(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _submittingComment ? null : _submitComment,
                        icon: _submittingComment
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.id)
          .collection('comments')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.chat_bubble_outline, size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 8),
                  Text(
                    'No responses yet',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _CommentCard(data: data);
          }).toList(),
        );
      },
    );
  }

  Future<void> _updateStatus(FeedbackStatus newStatus) async {
    await FirebaseFirestore.instance.collection('feedback').doc(widget.id).update({
      'status': newStatus.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Add a system comment about the status change
    final currentUser = OperatorStore.name.value ?? 'System';
    await FirebaseFirestore.instance
        .collection('feedback')
        .doc(widget.id)
        .collection('comments')
        .add({
      'text': 'Status changed to ${newStatus.label}',
      'author': currentUser,
      'isAdmin': _isAdmin,
      'isSystem': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _submittingComment = true);

    try {
      final currentUser = OperatorStore.name.value ?? 'Anonymous';
      
      final batch = FirebaseFirestore.instance.batch();
      
      // Add comment
      final commentRef = FirebaseFirestore.instance
          .collection('feedback')
          .doc(widget.id)
          .collection('comments')
          .doc();
      
      batch.set(commentRef, {
        'text': text,
        'author': currentUser,
        'isAdmin': _isAdmin,
        'isSystem': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // Update comment count
      final feedbackRef = FirebaseFirestore.instance.collection('feedback').doc(widget.id);
      batch.update(feedbackRef, {
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      await batch.commit();
      
      _commentController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submittingComment = false);
    }
  }
}

/// Card for displaying a comment
class _CommentCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _CommentCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = data['text'] as String? ?? '';
    final author = data['author'] as String? ?? 'Anonymous';
    final isAdmin = data['isAdmin'] as bool? ?? false;
    final isSystem = data['isSystem'] as bool? ?? false;
    final createdAt = data['createdAt'] as Timestamp?;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isAdmin ? cs.primaryContainer.withValues(alpha: 0.3) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isAdmin ? cs.primary : cs.primaryContainer,
                  child: Text(
                    author.isNotEmpty ? author[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 12,
                      color: isAdmin ? cs.onPrimary : cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  author,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isAdmin ? cs.primary : null,
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'DEV',
                      style: TextStyle(fontSize: 10, color: cs.onPrimary, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                const Spacer(),
                if (createdAt != null)
                  Text(
                    DateFormat('MMM d • h:mm a').format(createdAt.toDate()),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}
