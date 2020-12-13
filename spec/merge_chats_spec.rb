require_relative '../aoe2rec'

describe :merge_chats_core do
  it 'can merge chats in a typical game' do
    chats = [
      { time: 1000, player: 1, to: [1], message: "hi" },
      { time: 1200, player: 1, to: [2], message: "hi" },
      { time: 9000, player: 3, to: [2], message: "glhf" },
      { time: 9100, player: 3, to: [1], message: "glhf" },
      { time: 9200, player: 3, to: [3], message: "glhf" },
    ]
    merged_chats = merge_chats_core(chats)
    expect(merged_chats).to eq [
      { time: 1000, player: 1, to: [1, 2], message: "hi" },
      { time: 9000, player: 3, to: [2, 1, 3], message: "glhf" },
    ]
  end

  it 'does not merge two chats from the same replay' do
    pending
    # If both of these are in player 1's reply they must be separate messages.
    chats = [
      { time: 1000, player: 1, to: [1], message: "hi" },
      { time: 1100, player: 1, to: [1], message: "hi" },
    ]
    merged_chats = merge_chats_core(chats)
    expect(merged_chats).to eq chats
  end

end
