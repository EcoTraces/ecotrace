import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/domain/user_profile.dart';
import '../data/support_repository.dart';
import '../domain/support_ticket.dart';

class SupportDashboardScreen extends StatelessWidget {
  const SupportDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.currentUserName,
    required this.isAgent,
  });
  final SupportRepository repository;
  final String currentUserId, currentUserName;
  final bool isAgent;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: isAgent ? 3 : 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Customer support'),
        bottom: TabBar(
          tabs: [
            const Tab(icon: Icon(Icons.support_agent), text: 'Tickets'),
            const Tab(
              icon: Icon(Icons.menu_book_outlined),
              text: 'Help centre',
            ),
            if (isAgent)
              const Tab(
                icon: Icon(Icons.analytics_outlined),
                text: 'Analytics',
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreateSupportTicketScreen(
              repository: repository,
              currentUserId: currentUserId,
              currentUserName: currentUserName,
            ),
          ),
        ),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New ticket'),
      ),
      body: TabBarView(
        children: [
          _tickets(context),
          _knowledge(context),
          if (isAgent) _analytics(),
        ],
      ),
    ),
  );

  Widget _tickets(BuildContext context) => StreamBuilder<List<SupportTicket>>(
    stream: repository.watchTickets(userId: isAgent ? null : currentUserId),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('Unable to load tickets: ${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final tickets = snapshot.data!;
      if (tickets.isEmpty) {
        return const Center(child: Text('No support tickets yet.'));
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: tickets.length,
        itemBuilder: (context, index) {
          final ticket = tickets[index];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(_categoryIcon(ticket.category)),
              ),
              title: Text('${ticket.ticketNumber} • ${ticket.subject}'),
              subtitle: Text(
                '${ticket.category.label} • ${ticket.priority.name}\n${ticket.status.label}${ticket.agentName.isEmpty ? '' : ' • ${ticket.agentName}'}',
              ),
              isThreeLine: true,
              trailing: ticket.escalationLevel > 0
                  ? Badge(
                      label: Text('${ticket.escalationLevel}'),
                      child: const Icon(Icons.priority_high),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SupportTicketDetailScreen(
                    repository: repository,
                    ticketId: ticket.id,
                    currentUserId: currentUserId,
                    currentUserName: currentUserName,
                    isAgent: isAgent,
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _knowledge(
    BuildContext context,
  ) => StreamBuilder<List<KnowledgeArticle>>(
    stream: repository.watchKnowledge(includeDrafts: isAgent),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final articles = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          if (isAgent)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => _article(context),
                icon: const Icon(Icons.post_add),
                label: const Text('Add article'),
              ),
            ),
          if (articles.isEmpty)
            const ListTile(title: Text('No help articles published yet.')),
          for (final article in articles)
            Card(
              child: ExpansionTile(
                leading: Icon(
                  article.type == KnowledgeArticleType.faq
                      ? Icons.question_answer_outlined
                      : Icons.article_outlined,
                ),
                title: Text(article.title),
                subtitle: Text(
                  '${article.category} • ${article.type.name}${article.published ? '' : ' • Draft'}',
                ),
                onExpansionChanged: (open) {
                  if (open) repository.recordArticleView(article.id);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(article.content),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _analytics() => StreamBuilder<List<SupportTicket>>(
    stream: repository.watchTickets(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final analytics = SupportAnalytics.fromTickets(snapshot.data!);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metric(
                'Total tickets',
                analytics.total.toString(),
                Icons.confirmation_number_outlined,
              ),
              _metric(
                'Open',
                analytics.open.toString(),
                Icons.mark_chat_unread_outlined,
              ),
              _metric(
                'Resolved',
                analytics.resolved.toString(),
                Icons.task_alt,
              ),
              _metric(
                'Escalated',
                analytics.escalated.toString(),
                Icons.priority_high,
              ),
              _metric(
                'Avg. resolution',
                '${analytics.averageResolutionHours.toStringAsFixed(1)} h',
                Icons.timer_outlined,
              ),
              _metric(
                'Satisfaction',
                '${analytics.averageSatisfaction.toStringAsFixed(1)} / 5',
                Icons.star_outline,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Tickets by category',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final entry in analytics.byCategory.entries)
            ListTile(
              title: Text(entry.key.label),
              trailing: Text('${entry.value}'),
            ),
        ],
      );
    },
  );

  Future<void> _article(BuildContext context) async {
    var type = KnowledgeArticleType.faq;
    var published = true;
    final category = TextEditingController(text: 'General');
    final title = TextEditingController();
    final content = TextEditingController();
    final tags = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Knowledge-base article'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<KnowledgeArticleType>(
                      initialValue: type,
                      items: KnowledgeArticleType.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => type = value!),
                    ),
                    TextField(
                      controller: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: 'Question or title',
                      ),
                    ),
                    TextField(
                      controller: content,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Answer or article content',
                      ),
                    ),
                    TextField(
                      controller: tags,
                      decoration: const InputDecoration(
                        labelText: 'Tags, comma separated',
                      ),
                    ),
                    SwitchListTile(
                      value: published,
                      onChanged: (value) => setLocal(() => published = value),
                      title: const Text('Published'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runSupport(
        context,
        () => repository.saveArticle(
          type: type,
          category: category.text,
          title: title.text,
          content: content.text,
          tags: tags.text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(),
          published: published,
          actorId: currentUserId,
        ),
        'Article saved.',
      );
    }
    category.dispose();
    title.dispose();
    content.dispose();
    tags.dispose();
  }
}

class CreateSupportTicketScreen extends StatefulWidget {
  const CreateSupportTicketScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.currentUserName,
  });
  final SupportRepository repository;
  final String currentUserId, currentUserName;
  @override
  State<CreateSupportTicketScreen> createState() =>
      _CreateSupportTicketScreenState();
}

class _CreateSupportTicketScreenState extends State<CreateSupportTicketScreen> {
  ComplaintCategory category = ComplaintCategory.pickupService;
  TicketPriority priority = TicketPriority.normal;
  final subject = TextEditingController();
  final description = TextEditingController();
  final evidence = <Uint8List>[];
  bool saving = false;

  @override
  void dispose() {
    subject.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Submit support ticket')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<ComplaintCategory>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Complaint category'),
          items: ComplaintCategory.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setState(() => category = value!),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<TicketPriority>(
          initialValue: priority,
          decoration: const InputDecoration(labelText: 'Priority'),
          items: TicketPriority.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.name)),
              )
              .toList(),
          onChanged: (value) => setState(() => priority = value!),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: subject,
          decoration: const InputDecoration(labelText: 'Subject'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: description,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Describe your enquiry or complaint',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickEvidence,
          icon: const Icon(Icons.attach_file),
          label: Text('Attach evidence (${evidence.length})'),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: saving ? null : _submit,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Submit ticket'),
        ),
      ],
    ),
  );

  Future<void> _pickEvidence() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 75);
    for (final file in files) {
      evidence.add(await file.readAsBytes());
    }
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    setState(() => saving = true);
    try {
      await widget.repository.submitTicket(
        userId: widget.currentUserId,
        userName: widget.currentUserName,
        category: category,
        subject: subject.text,
        description: description.text,
        priority: priority,
        evidence: evidence,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to submit ticket: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class SupportTicketDetailScreen extends StatelessWidget {
  const SupportTicketDetailScreen({
    super.key,
    required this.repository,
    required this.ticketId,
    required this.currentUserId,
    required this.currentUserName,
    required this.isAgent,
  });
  final SupportRepository repository;
  final String ticketId, currentUserId, currentUserName;
  final bool isAgent;

  @override
  Widget build(BuildContext context) => StreamBuilder<SupportTicket>(
    stream: repository.watchTicket(ticketId),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final ticket = snapshot.data!;
      return Scaffold(
        appBar: AppBar(title: Text(ticket.ticketNumber)),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ticket.subject,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${ticket.category.label} • ${ticket.priority.name} • ${ticket.status.label}',
                          ),
                          if (isAgent) Text('Customer: ${ticket.userName}'),
                          if (ticket.agentName.isNotEmpty)
                            Text('Agent: ${ticket.agentName}'),
                          const Divider(),
                          Text(ticket.description),
                          if (ticket.escalationReason.isNotEmpty)
                            Text(
                              'Escalation: ${ticket.escalationReason}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (ticket.resolution.isNotEmpty)
                            Text(
                              'Resolution: ${ticket.resolution}',
                              style: const TextStyle(color: Colors.green),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (ticket.evidenceUrls.isNotEmpty) ...[
                    Text(
                      'Evidence',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(
                      height: 120,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: ticket.evidenceUrls
                            .map(
                              (url) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    width: 150,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                  if (isAgent) _agentActions(context, ticket),
                  if (!isAgent &&
                      ticket.status == TicketStatus.resolved &&
                      ticket.satisfactionRating == 0)
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _rate(context, ticket),
                          child: const Text('Rate resolution'),
                        ),
                        OutlinedButton(
                          onPressed: () => _runSupport(
                            context,
                            () => repository.reopen(ticket, currentUserId),
                            'Ticket reopened.',
                          ),
                          child: const Text('Reopen'),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Conversation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  StreamBuilder<List<TicketMessage>>(
                    stream: repository.watchMessages(
                      ticket.id,
                      includeInternal: isAgent,
                    ),
                    builder: (context, messageSnapshot) => Column(
                      children: [
                        for (final message
                            in messageSnapshot.data ?? const <TicketMessage>[])
                          Align(
                            alignment: message.senderId == currentUserId
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Card(
                              color: message.internal
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.tertiaryContainer
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${message.senderName}${message.internal ? ' • Internal note' : ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(message.body),
                                    for (final url in message.attachmentUrls)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Image.network(url, width: 180),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (ticket.status != TicketStatus.closed)
              _composer(context, ticket),
          ],
        ),
      );
    },
  );

  Widget _agentActions(BuildContext context, SupportTicket ticket) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonal(
          onPressed: () => _assign(context, ticket),
          child: const Text('Assign agent'),
        ),
        OutlinedButton(
          onPressed: () => _priority(context, ticket),
          child: const Text('Priority'),
        ),
        OutlinedButton(
          onPressed: () => _status(context, ticket),
          child: const Text('Status'),
        ),
        OutlinedButton(
          onPressed: () => _escalate(context, ticket),
          child: const Text('Escalate'),
        ),
        FilledButton(
          onPressed: ticket.isOpen ? () => _resolve(context, ticket) : null,
          child: const Text('Resolve'),
        ),
      ],
    ),
  );

  Widget _composer(BuildContext context, SupportTicket ticket) {
    final text = TextEditingController();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            IconButton(
              onPressed: () =>
                  _send(context, ticket, text, false, attach: true),
              icon: const Icon(Icons.attach_file),
            ),
            Expanded(
              child: TextField(
                controller: text,
                decoration: const InputDecoration(hintText: 'Write a message'),
              ),
            ),
            if (isAgent)
              IconButton(
                onPressed: () => _send(context, ticket, text, true),
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Internal note',
              ),
            IconButton.filled(
              onPressed: () => _send(context, ticket, text, false),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(
    BuildContext context,
    SupportTicket ticket,
    TextEditingController text,
    bool internal, {
    bool attach = false,
  }) async {
    final files = <Uint8List>[];
    if (attach) {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 75);
      for (final file in picked) {
        files.add(await file.readAsBytes());
      }
    }
    if (!context.mounted) return;
    await _runSupport(
      context,
      () => repository.addMessage(
        ticket,
        senderId: currentUserId,
        senderName: currentUserName,
        body: text.text,
        internal: internal,
        attachments: files,
      ),
      internal ? 'Internal note added.' : 'Message sent.',
    );
    text.clear();
  }

  Future<void> _assign(BuildContext context, SupportTicket ticket) async {
    final agents = await repository.watchAgents().first;
    if (!context.mounted || agents.isEmpty) return;
    UserProfile selected = agents.first;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Assign support agent'),
              content: DropdownButtonFormField<UserProfile>(
                initialValue: selected,
                items: agents
                    .map(
                      (agent) => DropdownMenuItem(
                        value: agent,
                        child: Text(
                          agent.displayName.isEmpty
                              ? agent.email
                              : agent.displayName,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setLocal(() => selected = value!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Assign'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runSupport(
        context,
        () => repository.assignAgent(ticket, selected, currentUserId),
        'Agent assigned.',
      );
    }
  }

  Future<void> _priority(BuildContext context, SupportTicket ticket) async {
    var value = ticket.priority;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Ticket priority'),
              content: DropdownButtonFormField<TicketPriority>(
                initialValue: value,
                items: TicketPriority.values
                    .map(
                      (priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority.name),
                      ),
                    )
                    .toList(),
                onChanged: (next) => setLocal(() => value = next!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runSupport(
        context,
        () => repository.updatePriority(ticket, value),
        'Priority updated.',
      );
    }
  }

  Future<void> _status(BuildContext context, SupportTicket ticket) async {
    var value = ticket.status;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Ticket status'),
              content: DropdownButtonFormField<TicketStatus>(
                initialValue: value,
                items: TicketStatus.values
                    .where(
                      (status) => ![
                        TicketStatus.resolved,
                        TicketStatus.closed,
                      ].contains(status),
                    )
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                    )
                    .toList(),
                onChanged: (next) => setLocal(() => value = next!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runSupport(
        context,
        () => repository.updateStatus(ticket, value),
        'Status updated.',
      );
    }
  }

  Future<void> _escalate(BuildContext context, SupportTicket ticket) async {
    final reason = TextEditingController();
    final ok = await _textDialog(
      context,
      'Escalate complaint',
      'Escalation reason',
      reason,
      'Escalate',
    );
    if (ok && context.mounted) {
      await _runSupport(
        context,
        () => repository.escalate(
          ticket,
          reason: reason.text,
          actorId: currentUserId,
        ),
        'Complaint escalated.',
      );
    }
    reason.dispose();
  }

  Future<void> _resolve(BuildContext context, SupportTicket ticket) async {
    final resolution = TextEditingController();
    final ok = await _textDialog(
      context,
      'Resolve complaint',
      'Resolution details',
      resolution,
      'Resolve',
    );
    if (ok && context.mounted) {
      await _runSupport(
        context,
        () => repository.resolve(
          ticket,
          resolution: resolution.text,
          actorId: currentUserId,
        ),
        'Complaint resolved.',
      );
    }
    resolution.dispose();
  }

  Future<void> _rate(BuildContext context, SupportTicket ticket) async {
    var rating = 5;
    final comment = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Rate support'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                      (index) => IconButton(
                        onPressed: () => setLocal(() => rating = index + 1),
                        icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                        ),
                      ),
                    ),
                  ),
                  TextField(
                    controller: comment,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Comment'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runSupport(
        context,
        () => repository.rate(ticket, rating: rating, comment: comment.text),
        'Thank you for your feedback.',
      );
    }
    comment.dispose();
  }
}

IconData _categoryIcon(ComplaintCategory category) => switch (category) {
  ComplaintCategory.pickupService => Icons.local_shipping_outlined,
  ComplaintCategory.collectionCentre => Icons.warehouse_outlined,
  ComplaintCategory.damagedItem => Icons.broken_image_outlined,
  ComplaintCategory.billingOrFee => Icons.receipt_long_outlined,
  ComplaintCategory.repairService => Icons.handyman_outlined,
  ComplaintCategory.recyclingService => Icons.recycling,
  ComplaintCategory.staffConduct => Icons.person_off_outlined,
  ComplaintCategory.dataPrivacy => Icons.privacy_tip_outlined,
  ComplaintCategory.technicalIssue => Icons.bug_report_outlined,
  ComplaintCategory.other => Icons.help_outline,
};

Widget _metric(String label, String value, IconData icon) => SizedBox(
  width: 170,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(label),
        ],
      ),
    ),
  ),
);

Future<bool> _textDialog(
  BuildContext context,
  String title,
  String label,
  TextEditingController controller,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _runSupport(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Support operation failed: $error')),
      );
    }
  }
}
