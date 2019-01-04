require 'erb'

@prng = Random.new

def rand63
  sprintf('0x%016x', @prng.rand(2**63) << 1)
end

ERB.new(DATA.read, nil, '-').run(binding)
__END__
module zobrist;

immutable ulong SIDE = 0x0000000000000001;

// zobrist.HAND[color_t][type_t][n]
immutable ulong[19][8][2] HAND = [
    <%- 2.times do -%>
    [
        <%- 8.times do -%>
        [<% 19.times do %><%= rand63 %>, <% end %>],
        <%- end -%>
    ],
    <%- end -%>
];

// zobrist.PSQ[square_t][index]
immutable ulong[81][29] PSQ = [
    <%- 28.times do |i| -%>
    // <%= i %>
    [
        <%- 9.times do -%>
        <% 9.times do %><%= rand63 %>, <% end %>
        <%- end -%>
    ],
    <%- end -%>
    // 28
    [
        <%- 9.times do -%>
        <% 9.times do %>0x0000000000000000, <% end %>
        <%- end -%>
    ],
];
