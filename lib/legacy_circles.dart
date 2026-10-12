/// The two circles that used to be read from the hosted JSON file now live in
/// Supabase as public channels (created by
/// supabase/migration_reminders_and_json_channels.sql). The ids below are
/// fixed so a user's existing read history can be carried over and so the
/// one-time "your circles moved to Channels" prompt knows what to offer.
///
/// Once old app versions are gone, this file (and the prompt) can be deleted.
class LegacyChannel {
  const LegacyChannel({required this.channelId, required this.name});

  final String channelId;
  final String name;
}

/// Old circle id -> the channel that replaced it.
const Map<String, LegacyChannel> legacyCircleChannels = {
  'xfc0001': LegacyChannel(
    channelId: 'f64127c5-22f8-50ee-be35-735967eeecd0',
    name: 'The Exchange Family Church',
  ),
  'emp0001': LegacyChannel(
    channelId: 'adabaeed-8478-5eda-9423-01ffb48b89c2',
    name: 'ICGC',
  ),
};

/// Old decree id -> the same decree's new channel-decree id.
const Map<String, String> legacyQuoteIdMap = {
  'xfc0001-quote-0001': '370a0e00-4708-5b46-a034-bc7a6e9c4b8e',
  'xfc0001-quote-0002': 'b37e768a-00ae-50f4-83f2-53438c327bac',
  'xfc0001-quote-0003': 'f475371a-113d-52e6-8b96-2834efe17653',
  'xfc0001-quote-0004': 'ebb760cf-0daf-5b86-b466-d1365264112c',
  'xfc0001-quote-0005': '187dce67-25e9-5a67-9f9d-c8a163df8847',
  'xfc0001-quote-0006': 'd0a2b637-f991-5c09-b731-137f54920cb8',
  'xfc0001-quote-0007': '4cbeef16-13c3-58a2-b229-5f96cae263f9',
  'emp0001-quote-0001': 'c5c2f4e7-3f17-5da3-8469-fd6a45c0ea89',
};
