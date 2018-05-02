require 'erb'

@prng = Random.new

def rand64
  sprintf('0x%016x', @prng.rand(2**64))
end

ERB.new(DATA.read, nil, '-').run(binding)
__END__

immutable ulong HASH_SEED_SIDE = <%= rand64 %>;

// HASH_SHEED_HAND[side_t][type_t][n]
immutable ulong[19][8][2] HASH_SEED_HAND = [
    <%- 2.times do -%>
    [
        <%- 8.times do -%>
        [<% 19.times do %><%= rand64 %>, <% end %>]
        <%- end -%>
    ],
    <%- end -%>
];

// HASH_SHEED_BOARD[square_t][index]
immutable ulong[100][30] HASH_SEED_BOARD = [
    <%- 13.times do |i| -%>
    // <%= i %>
    [
        0, <% 9.times do %>0,                  <% end %>
        <%- 9.times do -%>
        0, <% 9.times do %><%= rand64 %>, <% end %>
        <%- end -%>
    ],
    <%- end -%>
    <%- 2.times do -%>
    [
        <%- 9.times do -%>
        0, <% 9.times do %>0, <% end %>
        <%- end -%>
    ],
    <%- end -%>
    <%- 13.times do -%>
    [
        0, <% 9.times do %>0,                  <% end %>
        <%- 9.times do -%>
        0, <% 9.times do %><%= rand64 %>, <% end %>
        <%- end -%>
    ],
    <%- end -%>
];
