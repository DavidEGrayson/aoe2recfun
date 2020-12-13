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
    # If both of these are in player 1's reply they must be separate messages.
    chats = [
      { time: 1000, player: 1, to: [1], message: "hi" },
      { time: 1100, player: 1, to: [1], message: "hi" },
    ]
    merged_chats = merge_chats_core(chats)
    expect(merged_chats).to eq chats
  end

  it 'does not merge two chats more than 10 seconds apart' do
    chats = [
      { time: 1000, player: 1, to: [1], message: "hi" },
      { time: 12000, player: 1, to: [2], message: "hi" },
    ]
    merged_chats = merge_chats_core(chats)
    expect(merged_chats).to eq chats
  end

  it 'can handle a typical pause conversation' do
    chats = [
      { time: 1000, player: 2, to: [1], message: "sec" },
      { time: 1000, player: 2, to: [1], message: "sry go?" },
      { time: 1000, player: 1, to: [1], message: "14" },
      { time: 1000, player: 2, to: [2], message: "sec" },
      { time: 1000, player: 2, to: [2], message: "sry go?" },
      { time: 1000, player: 1, to: [2], message: "14" },
    ]
    merged_chats = merge_chats_core(chats)
    expect(merged_chats).to eq [
      { time: 1000, player: 2, to: [1, 2], message: "sec" },
      { time: 1000, player: 2, to: [1, 2], message: "sry go?" },
      { time: 1000, player: 1, to: [1, 2], message: "14" },
    ]
  end

  it 'cannot handle more a complex pause conversations yet' do
    chats = [
      { time: 1000, player: 2, to: [1], message: "you ok?" },
      { time: 1000, player: 1, to: [1], message: "yes" },

      { time: 1000, player: 2, to: [2], message: "hey bro" },
      { time: 1000, player: 2, to: [2], message: "you ok?" },
      { time: 1000, player: 1, to: [2], message: "yes" },

      { time: 1000, player: 2, to: [3], message: "hey bro" },
    ]
    merged_chats = merge_chats_core(chats)

    # Here's what the algorithm currently gives:
    expect(merged_chats).to eq [
      { time: 1000, player: 2, to: [1], message: "you ok?" },
      { time: 1000, player: 1, to: [1], message: "yes" },
      { time: 1000, player: 2, to: [2, 3], message: "hey bro" },
      { time: 1000, player: 2, to: [2], message: "you ok?" },
      { time: 1000, player: 1, to: [2], message: "yes" },
    ]

    # But it would be amazing if it could do this instead:
    pending 'not implemented'
    expect(merged_chats).to eq [
      { time: 1000, player: 2, to: [1, 2], message: "you ok?" },
      { time: 1000, player: 1, to: [1, 2], message: "yes" },
      { time: 1000, player: 2, to: [2, 3], message: "hey bro" },
    ]
  end
end
