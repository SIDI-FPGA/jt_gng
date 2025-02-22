/*  This file is part of JT_GNG.
    JT_GNG program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT_GNG program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT_GNG.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 19-2-2019 */

// 1943 Colour Mixer
// Schematics page 8/9

`timescale 1ns/1ps

module jt1943_colmix(
    input           rst,
    input           clk,    // 24 MHz
    input           cen12,
    input           cen6 /* synthesis direct_enable = 1 */,
    // pixel input from generator modules
    input [3:0]     char_pxl,        // character color code
    input [5:0]     scr1_pxl,
    input [5:0]     scr2_pxl,
    input [7:0]     obj_pxl,
    // Palette PROMs 12A, 13A, 14A, 12C
    input [7:0]     prog_addr,
    input           prom_red_we,
    input           prom_green_we,
    input           prom_blue_we,
    input           prom_prior_we,
    input [3:0]     prom_din,

    input           LVBL,
    input           LHBL,
    output  reg     LHBL_dly,
    output  reg     LVBL_dly,
    // Avatars
    input [3:0]     avatar_idx,
    input           pause,

    output reg [3:0] red,
    output reg [3:0] green,
    output reg [3:0] blue,
    // Debug
    input      [3:0] gfx_en
);

parameter BLANK_OFFSET  = 4,
          PALETTE_RED   = "../../../rom/1943/bm1.12a",
          PALETTE_GREEN = "../../../rom/1943/bm2.13a",
          PALETTE_BLUE  = "../../../rom/1943/bm3.14a",
          PALETTE_PRIOR = "../../../rom/1943/bm4.12c";
parameter SCRPLANES     = 2;    // 1 or 2

wire [7:0] dout_rg;
wire [3:0] dout_b;

reg [7:0] pixel_mux;
wire [3:0] selbus;

wire char_blank_b = gfx_en[0] & |(~char_pxl);
wire obj_blank_b  = gfx_en[3] & |(~obj_pxl[3:0]);
wire scr1_blank_b = gfx_en[1] & |(~scr1_pxl[3:0]);
reg [7:0] seladdr;

reg [3:0] char_pxl_1;
reg [5:0] scr1_pxl_1;
reg [5:0] scr2_pxl_1;
reg [7:0] obj_pxl_1;

// latch for one clock cycle to wait for the selbus signal
always @(posedge clk) if(cen6) begin
    char_pxl_1  <= char_pxl;
    scr1_pxl_1  <= scr1_pxl;
    scr2_pxl_1  <= scr2_pxl;
    obj_pxl_1   <= obj_pxl;
    if( SCRPLANES == 2 )
        // 1943
        seladdr     <= { 3'b0, char_blank_b, obj_blank_b, obj_pxl[7:6], scr1_blank_b };
    else
        // GunSmoke
        seladdr     <= { 4'b0, char_blank_b, obj_blank_b, obj_pxl[6], 1'b0 }; // 6 or 7?
end

always @(posedge clk) if(cen6) begin
    if( SCRPLANES == 2 )
        case( selbus[1:0] ) // 1943
            2'b00: pixel_mux[5:0] <= scr2_pxl_1;
            2'b01: pixel_mux[5:0] <= scr1_pxl_1;
            2'b10: pixel_mux[5:0] <=  obj_pxl_1[5:0];
            2'b11: pixel_mux[5:0] <= { 2'b0, char_pxl_1 };
        endcase // selbus[1:0]
    else
        case( selbus[1:0] ) // GunSmoke
            2'b00: pixel_mux[5:0] <= scr1_pxl_1;
            2'b10: pixel_mux[5:0] <=  obj_pxl_1[5:0];
            2'b11: pixel_mux[5:0] <= { 2'b0, char_pxl_1 };
        endcase // selbus[1:0]

    pixel_mux[7:6] <= selbus[3:2];
end

wire [1:0] pre_BL;

jtgng_sh #(.width(2),.stages(BLANK_OFFSET-1)) u_hb_dly(
    .clk    ( clk      ),
    .clk_en ( cen6     ),
    .din    ( {LHBL, LVBL}     ),
    .drop   ( pre_BL   )
);

always @(posedge clk) if(cen6) {LHBL_dly, LVBL_dly} <= pre_BL;

// palette ROM
wire [3:0] pal_red, pal_green, pal_blue;

jtgng_prom #(.aw(8),.dw(4),.simfile(PALETTE_RED)) u_red(
    .clk    ( clk         ),
    .cen    ( 1'b1        ),
    .data   ( prom_din    ),
    .rd_addr( pixel_mux   ),
    .wr_addr( prog_addr   ),
    .we     ( prom_red_we ),
    .q      ( pal_red     )
);

jtgng_prom #(.aw(8),.dw(4),.simfile(PALETTE_GREEN)) u_green(
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .data   ( prom_din      ),
    .rd_addr( pixel_mux     ),
    .wr_addr( prog_addr     ),
    .we     ( prom_green_we ),
    .q      ( pal_green     )
);

jtgng_prom #(.aw(8),.dw(4),.simfile(PALETTE_BLUE)) u_blue(
    .clk    ( clk          ),
    .cen    ( 1'b1         ),
    .data   ( prom_din     ),
    .rd_addr( pixel_mux    ),
    .wr_addr( prog_addr    ),
    .we     ( prom_blue_we ),
    .q      ( pal_blue     )
);

// Clock must be faster than 6MHz so selbus is ready for the next
// 6MHz clock cycle:
jtgng_prom #(.aw(8),.dw(4),.simfile(PALETTE_PRIOR)) u_selbus(
    .clk    ( clk           ),
    .cen    ( 1'b1          ),
    .data   ( prom_din      ),
    .rd_addr( seladdr       ),
    .wr_addr( prog_addr     ),
    .we     ( prom_prior_we ),
    .q      ( selbus        )
);


`ifdef AVATARS
wire [11:0] avatar_pal;
// Objects have their own palette during pause
wire [ 7:0] avatar_addr = { avatar_idx, obj_pxl[0], obj_pxl[1], obj_pxl[2], obj_pxl[3] };

jtgng_ram #(.dw(12),.aw(8), .synfile("avatar_pal.hex"),.cen_rd(1))u_avatars(
    .clk    ( clk           ),
    .cen    ( pause         ),  // tiny power saving when not in pause
    .data   ( 12'd0         ),
    .addr   ( avatar_addr   ),
    .we     ( 1'b0          ),
    .q      ( avatar_pal    )
);

reg [1:0] obj_sel;

always @(posedge clk) if(cen6) begin
    obj_sel[0] <= selbus[1:0]==2'b10;
    obj_sel[1] <= obj_sel[0];
end
`else 
wire [11:0] avatar_pal = {pal_red, pal_green, pal_blue};
wire [1:0] obj_sel = 2'b00;
`endif

always @(posedge clk) if(cen6) begin
    { red, green, blue } <= 
        pre_BL==2'b11 ?
            ( pause && obj_sel[1] ? avatar_pal : {pal_red, pal_green, pal_blue} ) :
            12'd0; // blanking
end

endmodule // jtgng_colmix