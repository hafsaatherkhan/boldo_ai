import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/provider.dart';
import '../theme.dart';
import 'provider_detail_screen.dart';
import '../widgets/glass_card.dart';
import '../widgets/boldo_app_bar.dart';
import '../widgets/boldo_bottom_bar.dart';
import '../../main.dart';
import '../../models/ranking_output.dart';

class ProviderListingScreen extends StatefulWidget {
  final String requestedService;
  final String? initialTopChoiceId;
  final Future<RankingOutput?>? rankingFuture;

  const ProviderListingScreen({
    super.key,
    required this.requestedService,
    this.initialTopChoiceId,
    this.rankingFuture,
  });

  @override
  State<ProviderListingScreen> createState() => _ProviderListingScreenState();
}

class _ProviderListingScreenState extends State<ProviderListingScreen> {
  bool _isRanking = false;
  String? _topChoiceId;
  RankingOutput? _rankingOutput;
  final List<String> _rankingPhrases = [
    'Analyzing available providers...',
    'Calculating distances and ETAs...',
    'Checking past reliability scores...',
    'Comparing pricing vs. quality...',
    'Finalizing best match...',
  ];

  @override
  void initState() {
    super.initState();
    _topChoiceId = widget.initialTopChoiceId;

    if (widget.rankingFuture != null) {
      _isRanking = true;
      
      widget.rankingFuture!.then((output) async {
        if (!mounted) return;
        setState(() {
          _isRanking = false;
        });

        if (output != null) {
          setState(() {
            _rankingOutput = output;
            if (output.topChoice != null) {
              _topChoiceId = output.topChoice!.providerId;
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Normalizing requestedService to match seeder collection value
    // Let's determine correct Firestore field value based on common terms
    String normalizedService = 'Plumbing';
    final lowerInput = widget.requestedService.toLowerCase();
    if (lowerInput.contains('electrician') || lowerInput.contains('bijli')) {
      normalizedService = 'Electrical';
    } else if (lowerInput.contains('ac') || lowerInput.contains('technician')) {
      normalizedService = 'AC Repair';
    } else if (lowerInput.contains('cleaner') || lowerInput.contains('safai')) {
      normalizedService = 'Cleaning';
    } else if (lowerInput.contains('paint') || lowerInput.contains('painter')) {
      normalizedService = 'Painting';
    } else if (lowerInput.contains('carpenter') || lowerInput.contains('wood')) {
      normalizedService = 'Carpentry';
    } else if (lowerInput.contains('handyman')) {
      normalizedService = 'General';
    }

    return Scaffold(
      extendBody: true,
      appBar: const BolDoAppBar(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('providers')
            .where('serviceType', isEqualTo: normalizedService)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No matching providers found in your location.',
                style: TextStyle(color: BolDoTheme.textSecondary),
              ),
            );
          }

          final providers = snapshot.data!.docs.map((doc) {
            return Provider.fromJson(doc.data() as Map<String, dynamic>, doc.id);
          }).toList();

          // Sort providers
          providers.sort((a, b) {
            if (_rankingOutput != null) {
              // Try to find AI generated scores
              double scoreA = 0.0;
              double scoreB = 0.0;
              
              try {
                final rpA = _rankingOutput!.rankedProviders.firstWhere((p) => p.providerId == a.providerId);
                scoreA = rpA.score;
              } catch (_) {}
              
              try {
                final rpB = _rankingOutput!.rankedProviders.firstWhere((p) => p.providerId == b.providerId);
                scoreB = rpB.score;
              } catch (_) {}

              // If AI gave them different scores, sort by AI score (highest first)
              if (scoreA != scoreB) {
                return scoreB.compareTo(scoreA);
              }
            }
            
            // Fallback: If no AI ranking yet or scores are identical, use top choice & raw rating
            if (a.providerId == _topChoiceId) return -1;
            if (b.providerId == _topChoiceId) return 1;
            return b.rating.compareTo(a.rating);
          });

          return Column(
            children: [
              if (_isRanking)
                _RankingProgressIsland(phrases: _rankingPhrases),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(16.0, _isRanking ? 0 : 16.0, 16.0, 100.0),
                  itemCount: providers.length,
                  itemBuilder: (context, index) {
                    final provider = providers[index];
                    final isTopChoice = provider.providerId == _topChoiceId;
                    
                    String? reasoning;
                    if (_rankingOutput != null) {
                      if (isTopChoice) {
                        reasoning = _rankingOutput!.topChoice?.reasoning;
                      } else {
                        try {
                          final rp = _rankingOutput!.rankedProviders.firstWhere(
                            (p) => p.providerId == provider.providerId
                          );
                          reasoning = rp.reasoning;
                        } catch (_) {}
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProviderDetailScreen(
                                provider: provider,
                                isTopChoice: isTopChoice,
                                reasoning: reasoning,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: isTopChoice
                                ? [
                                    const BoxShadow(
                                      color: BolDoTheme.primary,
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : [],
                          ),
                          child: GlassCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Avatar / Icon
                                Container(
                                  height: 60,
                                  width: 60,
                                  decoration: BoxDecoration(
                                    color: isTopChoice
                                        ? BolDoTheme.primary.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.05),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isTopChoice ? Icons.star : Icons.person,
                                    color: isTopChoice ? BolDoTheme.primary : Colors.white70,
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // Text Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            provider.name,
                                            style: const TextStyle(
                                              color: BolDoTheme.textPrimary,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (isTopChoice) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: BolDoTheme.primary,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'AI TOP CHOICE',
                                                style: TextStyle(
                                                  color: BolDoTheme.background,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          ]
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Area: ${provider.locationArea}',
                                        style: const TextStyle(
                                          color: BolDoTheme.textSecondary,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.star, color: Colors.amber, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${provider.rating}',
                                            style: const TextStyle(
                                              color: BolDoTheme.textPrimary,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Icon(Icons.verified, color: BolDoTheme.secondary, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Reliability: ${provider.reliabilityScore}%',
                                            style: const TextStyle(
                                              color: BolDoTheme.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (reasoning != null && reasoning.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isTopChoice 
                                                ? Theme.of(context).colorScheme.primary.withOpacity(0.1) 
                                                : Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isTopChoice 
                                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.3) 
                                                  : Colors.transparent
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.auto_awesome, 
                                                size: 14, 
                                                color: isTopChoice 
                                                    ? Theme.of(context).colorScheme.primary 
                                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.5)
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  reasoning,
                                                  style: TextStyle(
                                                    color: isTopChoice 
                                                        ? Theme.of(context).colorScheme.primary 
                                                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: Colors.white30),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: const BolDoBottomBar(isHome: false),
    );
  }
}

class _RankingProgressIsland extends StatefulWidget {
  final List<String> phrases;
  const _RankingProgressIsland({Key? key, required this.phrases}) : super(key: key);

  @override
  State<_RankingProgressIsland> createState() => _RankingProgressIslandState();
}

class _RankingProgressIslandState extends State<_RankingProgressIsland> {
  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_step < widget.phrases.length - 1) {
          _step++;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24), // Dynamic island rounded shape
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: SizedBox(
              width: 18, 
              height: 18, 
              child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_step + 1, (index) {
                final isCurrent = index == _step;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Icon(
                          isCurrent ? Icons.circle_outlined : Icons.check_circle, 
                          size: 14, 
                          color: isCurrent 
                              ? Theme.of(context).colorScheme.onSurface.withOpacity(0.3) 
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.phrases[index],
                          style: TextStyle(
                            color: isCurrent 
                              ? Theme.of(context).textTheme.bodyLarge?.color 
                              : Theme.of(context).colorScheme.primary.withOpacity(0.8),
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

