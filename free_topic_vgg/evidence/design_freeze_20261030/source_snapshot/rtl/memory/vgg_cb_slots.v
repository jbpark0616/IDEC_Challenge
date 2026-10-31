`default_nettype none
// Single-producer / single-consumer CB ownership. Payload remains in SRAM.
//
// Default: FREE --reserve--> RESERVED --commit--> READY --acquire--> READING.
// EARLY_READ permits acquisition while RESERVED; commit seals the live slot
// without revoking its consumer lease. Payload validity is tracked separately.
// In either mode, release requires both producer commit and last consumer use.
//
// A slot remains occupied while being filled AND while being read/reused.
// Each side may own one in-progress slot; the other slots can be queued READY.
module vgg_cb_slots #(
    parameter integer SLOT_BITS = 3,
    parameter integer EARLY_READ = 0,
    parameter RUNTIME_SLOTS = 1'b0
) (
    input wire clk, rst_n, clear,
    input wire [SLOT_BITS:0] slot_limit,

    // Producer reserves storage and commits after its final payload write.
    input wire reserve_valid,
    output wire reserve_ready,
    output wire [SLOT_BITS-1:0] producer_slot,
    input wire commit_valid,
    output wire commit_ready,

    // Consumer acquires a slot and releases it after its last use.
    output wire available,
    input wire acquire,
    output wire [SLOT_BITS-1:0] consumer_slot,
    input wire release_valid,
    output wire release_ready,

    output wire [SLOT_BITS:0] occupancy
);
    localparam integer SLOTS = 1 << SLOT_BITS;
    localparam FREE = 0, RESERVED = 1, READY = 2, READING = 3;

    reg [1:0] owner [0:SLOTS-1];
    reg [SLOT_BITS-1:0] wr_ptr, rd_ptr;
    reg [SLOT_BITS:0] used;
    reg [SLOTS-1:0] sealed;

    assign producer_slot = wr_ptr;
    assign consumer_slot = rd_ptr;
    assign reserve_ready = owner[wr_ptr] == FREE;
    assign commit_ready  = owner[wr_ptr] == RESERVED
                         || (EARLY_READ && owner[wr_ptr] == READING);
    // Early acquisition grants ownership, not permission to read unwritten V.
    // The operand boundary publishes a separate completed-channel watermark.
    assign available     = owner[rd_ptr] == READY
                         || (EARLY_READ && owner[rd_ptr] == RESERVED);
    assign release_ready = owner[rd_ptr] == READING && sealed[rd_ptr];
    assign occupancy     = used;

    wire reserve_fire = reserve_valid && reserve_ready;
    wire release_fire = release_valid && release_ready;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            used <= 0;
            sealed <= 0;
            for (i = 0; i < SLOTS; i = i + 1)
                owner[i] <= FREE;
        end else if (clear) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            used <= 0;
            sealed <= 0;
            for (i = 0; i < SLOTS; i = i + 1)
                owner[i] <= FREE;
        end else begin
            // Producer advances only after its final payload write.
            if (reserve_fire) begin
                owner[wr_ptr] <= RESERVED;
                sealed[wr_ptr] <= 1'b0;
            end
            if (commit_valid && commit_ready) begin
                if (owner[wr_ptr] != READING) owner[wr_ptr] <= READY;
                sealed[wr_ptr] <= 1'b1;
                wr_ptr <= RUNTIME_SLOTS && {1'b0,wr_ptr}==slot_limit-1'b1
                        ? {SLOT_BITS{1'b0}} : wr_ptr + 1'b1;
            end

            // Acquiring does not free storage. All K reuses finish first.
            if (acquire && available)
                owner[rd_ptr] <= READING;
            if (release_fire) begin
                owner[rd_ptr] <= FREE;
                rd_ptr <= RUNTIME_SLOTS && {1'b0,rd_ptr}==slot_limit-1'b1
                        ? {SLOT_BITS{1'b0}} : rd_ptr + 1'b1;
            end

            // Simultaneous reserve/release leaves occupancy unchanged.
            case ({reserve_fire, release_fire})
                2'b10: used <= used + 1'b1;
                2'b01: used <= used - 1'b1;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
