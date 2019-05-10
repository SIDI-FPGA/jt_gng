//============================================================================
//  Arcade: 1943  by Jose Tejada Gomez. Twitter: @topapate
//
//  Port to MiSTer
//  Thanks to Sorgelig for his continuous support
//  Original repository: http://github.com/jotego/jt_gng
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

`timescale 1ns/1ps

module emu
(
    //Master input clock
    input         CLK_50M,

    //Async reset from top-level module.
    //Can be used as initial reset.
    input         RESET,

    //Must be passed to hps_io module
    inout  [44:0] HPS_BUS,

    //Base video clock. Usually equals to CLK_SYS.
    output        VGA_CLK,

    //Multiple resolutions are supported using different VGA_CE rates.
    //Must be based on CLK_VIDEO
    output        VGA_CE,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,    // = ~(VBlank | HBlank)

    //Base video clock. Usually equals to CLK_SYS.
    output        HDMI_CLK,

    //Multiple resolutions are supported using different HDMI_CE rates.
    //Must be based on CLK_VIDEO
    output        HDMI_CE,

    output  [7:0] HDMI_R,
    output  [7:0] HDMI_G,
    output  [7:0] HDMI_B,
    output        HDMI_HS,
    output        HDMI_VS,
    output        HDMI_DE,   // = ~(VBlank | HBlank)
    output  [1:0] HDMI_SL,   // scanlines fx

    //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
    output  [7:0] HDMI_ARX,
    output  [7:0] HDMI_ARY,

    output        LED_USER,  // 1 - ON, 0 - OFF.

    // b[1]: 0 - LED status is system status OR'd with b[0]
    //       1 - LED status is controled solely by b[0]
    // hint: supply 2'b00 to let the system control the LED.
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,

    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned

    //SDRAM interface with lower latency
    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE
);

`include "build_id.v"
localparam CONF_STR = {
    "A.1943;;",
    "-;",
    "F,rom;",
    "O1,Aspect Ratio,Original,Wide;",
    "O2,Orientation,Vert,Horz;",
    "O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
    "-;",
    "OCD,Difficulty,Normal,Easy,Hard,Very hard;",
    // "O67,Lives,3,1,2,5;",
    // "O89,Bonus,30/100,30/80,20/100,20/80;",
    "OA,Invulnerability,No,Yes;",
    "-;",
    "R0,Reset;",
    "J,Fire,Bomb,Start 1P,Start 2P,Coin,Pause;",
    "V,v",`BUILD_DATE, " http://patreon.com/topapate;"
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
wire cen12, cen6, cen3, cen1p5;
wire pll_locked;

pll pll(
    .refclk     ( CLK_50M    ),
    .rst        ( 1'b0       ),
    .locked     ( pll_locked ),
    .outclk_0   ( clk_sys    ),
    .outclk_1   ( SDRAM_CLK  )
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;

wire [10:0] ps2_key;

wire [15:0] joy_0, joy_1;

wire        forced_scandoubler;
wire        downloading;

assign LED_USER  = { 1'b0, downloading };
assign LED_DISK  = 2'b0;
assign LED_POWER = 2'b0;

assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd3;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd4;

wire ps2_kbd_clk, ps2_kbd_data;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
    .clk_sys          ( clk_sys        ),
    .HPS_BUS          ( HPS_BUS        ),

    .conf_str         ( CONF_STR       ),

    .buttons          ( buttons        ),
    .status           ( status         ),
    .forced_scandoubler(forced_scandoubler),

    .ioctl_download(downloading),
    .ioctl_wr         ( ioctl_wr       ),
    .ioctl_addr       ( ioctl_addr     ),
    .ioctl_dout       ( ioctl_data     ),

    .joystick_0       ( joy_0          ),
    .joystick_1       ( joy_1          ),
    //.ps2_key        ( ps2_key       )
    .ps2_kbd_clk_out  ( ps2_kbd_clk    ),
    .ps2_kbd_data_out ( ps2_kbd_data   )
);


///////////////////////////////////////////////////////////////////

wire hblank, vblank;
wire hs, vs;
wire [3:0] r,g,b;

`ifndef SIMULATION
arcade_rotate_fx #(256,224,12,1) arcade_video
(
    .*, // VGA_ and HDMI_ pins

    .clk_video(clk_sys),
    .ce_pix(cen6),

    .RGB_in({r,g,b}),
    .HBlank(~hblank),
    .VBlank(~vblank),
    .HSync(hs),
    .VSync(vs),

    .fx(status[5:3]),
    .no_rotate(status[2])
);
`else
    assign VGA_VS = vs;
    assign VGA_HS = hs;
    assign VGA_R  = r;
    assign VGA_G  = g;
    assign VGA_B  = b;
    assign VGA_CE = cen6;
    assign VGA_CLK= clk_sys;
`endif


wire dip_upright = 1'b1;
wire dip_credits2p = 1'b1;
reg [3:0] dip_level;
wire dip_demosnd = 1'b0;
wire dip_continue = 1'b1;
wire [2:0] dip_price2 = 3'b100;
wire [2:0] dip_price1 = ~3'b0;

// play level
always @(*)
    case( status[13:12] )
        2'b00: dip_level = 4'b0111; // normal
        2'b01: dip_level = 4'b1111; // easy
        2'b10: dip_level = 4'b0011; // hard
        2'b11: dip_level = 4'b0000; // very hard
    endcase // status[3:2]

///////////////////////////////////////////////////////////////////

wire rst_req = RESET | status[0] | buttons[1];

wire         prog_we;
wire [21:0]  prog_addr;
wire [ 7:0]  prog_data;
wire [ 1:0]  prog_mask;

// SDRAM
wire         loop_rst;
wire         sdram_req;
wire [31:0]  data_read;
wire [21:0]  sdram_addr;
wire         data_rdy;
wire         sdram_ack;
wire         refresh_en;

wire [9:0]   game_joystick1, game_joystick2;
wire [1:0]   game_coin, game_start;
wire         game_rst;
wire [3:0]   gfx_en;

jtgng_board u_board(
    .rst            (                ),    // use as synchrnous reset
    .rst_n          (                ),    // use as asynchronous reset
    .game_rst       ( game_rst       ),
    // reset forcing signals:
    .dip_flip       ( 1'b0           ), // A change in dip_flip implies a reset
    .rst_req        ( rst_req        ),

    .clk_sys        ( clk_sys        ),
    .clk_rom        ( clk_sys        ),

    // SDRAM controller - game interface
    .loop_rst       ( loop_rst       ),
    .sdram_req      ( sdram_req      ),
    .data_read      ( data_read      ),
    .data_rdy       ( data_rdy       ),
    .refresh_en     ( refresh_en     ),
    .sdram_addr     ( sdram_addr     ),
    .sdram_ack      ( sdram_ack      ),
    // ROM-load interface
    .downloading    ( downloading    ),
    .prog_we        ( prog_we        ),
    .prog_addr      ( prog_addr      ),
    .prog_data      ( prog_data      ),
    .prog_mask      ( prog_mask      ),
    // SDRAM interface
    .SDRAM_DQ       ( SDRAM_DQ       ),
    .SDRAM_A        ( SDRAM_A        ),
    .SDRAM_DQML     ( SDRAM_DQML     ),
    .SDRAM_DQMH     ( SDRAM_DQMH     ),
    .SDRAM_nWE      ( SDRAM_nWE      ),
    .SDRAM_nCAS     ( SDRAM_nCAS     ),
    .SDRAM_nRAS     ( SDRAM_nRAS     ),
    .SDRAM_nCS      ( SDRAM_nCS      ),
    .SDRAM_BA       ( SDRAM_BA       ),
    .SDRAM_CKE      ( SDRAM_CKE      ),
    // keyboard
    .ps2_kbd_clk    ( ps2_kbd_clk    ),
    .ps2_kbd_data   ( ps2_kbd_data   ),
    // joystick
    .board_joystick1( joy_0[9:0]     ),
    .board_joystick2( joy_1[9:0]     ),
    // joystick
    .game_joystick1 ( game_joystick1 ),
    .game_joystick2 ( game_joystick2 ),
    .game_coin      ( game_coin      ),
    .game_start     ( game_start     ),
    .game_pause     ( game_pause     ),
    .game_service   (                ), // unused
    // GFX enable
    .gfx_en         ( gfx_en         )
);

jt1943_game #(.CLK_SPEED(48)) u_game
(
    .rst           ( rst_req         ),

    .clk_rom       ( clk_sys         ),
    .clk           ( clk_sys         ),
    .cen12         ( cen12           ),
    .cen6          ( cen6            ),
    .cen3          ( cen3            ),
    .cen1p5        ( cen1p5          ),

    .red           ( r               ),
    .green         ( g               ),
    .blue          ( b               ),
    .LHBL          ( hblank          ),
    .LVBL          ( vblank          ),
    .HS            ( hs              ),
    .VS            ( vs              ),

    .start_button  ( game_start      ),
    .coin_input    ( game_coin       ),
    .joystick1     ( game_joystick1[6:0] ),
    .joystick2     ( game_joystick2[6:0] ),

    // Sound control
    .enable_fm    ( 1'b1             ),
    .enable_psg   ( 1'b1             ),
    // PROM programming
    .ioctl_addr   ( ioctl_addr[21:0] ),
    .ioctl_data   ( ioctl_data       ),
    .ioctl_wr     ( ioctl_wr         ),
    .prog_addr    ( prog_addr        ),
    .prog_data    ( prog_data        ),
    .prog_mask    ( prog_mask        ),
    .prog_we      ( prog_we          ),

    // ROM load
    .downloading  ( downloading      ),
    .loop_rst     ( loop_rst         ),
    .sdram_req    ( sdram_req        ),
    .sdram_addr   ( sdram_addr       ),
    .data_read    ( data_read        ),
    .sdram_ack    ( sdram_ack        ),
    .data_rdy     ( data_rdy         ),
    .refresh_en   ( refresh_en       ),

    .cheat_invincible( status[10]    ),

    .dip_test     ( ~btn_test        ),
    .dip_pause    ( ~game_pause      ),
    .dip_upright  ( dip_upright      ),
    .dip_credits2p( dip_credits2p    ),
    .dip_level    ( dip_level        ),
    .dip_demosnd  ( dip_demosnd      ),
    .dip_continue ( dip_continue     ),
    .dip_price2   ( dip_price2       ),
    .dip_price1   ( dip_price1       ),
    .dip_flip     ( 1'b0             ),

    .snd          ( AUDIO_L          ),
    .gfx_en       ( ~4'b0            ),

    // unconnected
    .coin_cnt     (                  ),
    .sample       (                  )
);

assign AUDIO_R = AUDIO_L;
assign AUDIO_S = 1;

endmodule
