import type { MessageKey } from "../i18n/messages.js";
import type { ChatContext } from "../memory/schema.js";

/**
 * Whether the chat (ADR-604) is in Doddy Web's menu and routes. It answers from the account today
 * (apps, documents, activity); notes, conversations and Logbook join as the iPhone sends them.
 */
export const CHAT_ENABLED = true;

/**
 * The questions offered on an empty chat, picked from what the chat can actually read now, so a
 * suggestion never leads to "that part is off". At most four.
 */
export function suggestionsFor(context: ChatContext | undefined): MessageKey[] {
  const picks: MessageKey[] = [];
  if (context?.logbook.enabled && context.logbook.days > 0) picks.push("chat.suggest.week", "chat.suggest.when", "chat.suggest.how");
  if (context?.memory.notes && context.memory.noteCount > 0) picks.push("chat.suggest.notes");
  if (context?.memory.conversations && context.memory.conversationCount > 0) picks.push("chat.suggest.lastTalk");
  if (context && context.activity.count > 0) picks.push("chat.suggest.activity");
  if (context && context.documents.count > 0) picks.push("chat.suggest.documents");
  picks.push("chat.suggest.apps", "chat.suggest.account");
  return [...new Set(picks)].slice(0, 4);
}
