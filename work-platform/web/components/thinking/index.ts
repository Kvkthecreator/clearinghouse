/**
 * Thinking Partner Components
 *
 * Chat-first architecture components for Thinking Partner.
 *
 * See: /docs/architecture/CHAT_FIRST_ARCHITECTURE_V1.md
 */

// Core chat components
export { TPChatInterface } from './TPChatInterface';
export { TPMessageList } from './TPMessageList';
export { TPSidebar } from './TPSidebar';

// Chat-first layout
export {
  ChatFirstLayout,
  ChatFirstLayoutProvider,
  useChatFirstLayout,
  type DetailTab,
} from './ChatFirstLayout';

// Chat cards (rich in-chat displays)
export {
  ContextChangeCard,
  ContextChangesGroup,
  WorkOutputCard,
  WorkOutputCarousel,
  RecipeProgressCard,
  ExecutionStepsTimeline,
} from './chat-cards';

// Detail panels
export {
  ContextDetailPanel,
  OutputsDetailPanel,
  TicketsDetailPanel,
} from './detail-panels';
