//============================================================================
//  Arcade: Demolition Derby by DarFPGA
//
//  Port to MiSTer
//  Copyright (C) 2019 Sorgelig
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

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

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
	output        VGA_F1,

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
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

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
	output        SDRAM_nWE, 

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

//assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd3;
//assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd4;
//assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd21 : 8'd20;
//;assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd20 : 8'd21;
assign HDMI_ARX = status[1] ? 8'd16 : 8'd4;
assign HDMI_ARY = status[1] ? 8'd9  : 8'd3;


`include "build_id.v" 
localparam CONF_STR = {
	"A.DDERBY;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	//"H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O6,Service,Off,On;",
	//"O7,Swap Joystick,Off,On;",
	"O8,Players,2,4;",
	"O9,Difficulty,Normal,Hard;",
	"OA,Trophy Girl,Full,Limited;",
	"-;",
	"OD,Video Mode,15KHz,31KHz;",
	"OC,Audio,Mono,Stereo;",
	"-;",
	"R0,Reset;",
	"J1,Forward,Reverse,Start,Coin;",
	"jn,A,B,X,Y,L,R,Start;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys,clk_80M;
wire clk_mem = clk_80M;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 40M
	.outclk_1(clk_80M), // 80M
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire  [9:0] audio;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joystick_0, joystick_1, joystick_2, joystick_3 ;

wire [15:0] joy_a;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask(direct_video),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),
	.joystick_analog_0(joy_a),
	.ps2_key(ps2_key)
);

wire [15:0] rom_addr;
wire [15:0] rom_do;
wire [14:0] snd_addr;
wire [15:0] snd_do;
wire [14:0] sp_addr;
wire [31:0] sp_do;

// ROM structure:
//  0000 -  FFFF - Main ROM (8 bit)
// 				  - Super Sound board ROM (8 bit)
// 10000 - 13FFF - CSD ROM (16 bit)
// 14000 - 33FFF - Sprite ROMs (32 bit)
// 34000 - 37FFF - BG ROMs

wire [24:0] sp_ioctl_addr = ioctl_addr - 17'h14000; ////Sprite offset
wire [24:0] dl_addr = ioctl_addr - 18'h34000; //Background offset


reg port1_req, port2_req;
sdram sdram
(
	.*,
	.init_n        ( pll_locked   ),
	.clk           ( clk_mem      ),

	// port1 used for main + sound CPUs
	.port1_req     ( port1_req    ),
	.port1_ack     ( ),
	.port1_a       ( ioctl_addr[23:1] ),
	.port1_ds      ( {ioctl_addr[0], ~ioctl_addr[0]} ),
	.port1_we      ( ioctl_download ),
	.port1_d       ( {ioctl_dout, ioctl_dout} ),
	.port1_q       ( ),

	.cpu1_addr     ( ioctl_download ? 16'hffff : {1'b0, rom_addr[15:1]} ),
	.cpu1_q        ( rom_do ),
	.cpu2_addr     ( cpu2_addr ),//Turbo Cheap Squeak
	.cpu2_q        ( snd_do ),

	// port2 for sprite graphics
	.port2_req     ( port2_req ),
	.port2_ack     ( ),
	.port2_a       ( {sp_ioctl_addr[18:17], sp_ioctl_addr[14:0], sp_ioctl_addr[16]} ), // merge sprite roms to 32-bit wide words
	.port2_ds      ( {sp_ioctl_addr[15], ~sp_ioctl_addr[15]} ),
	.port2_we      ( ioctl_download ),
	.port2_d       ( {ioctl_dout, ioctl_dout} ),
	.port2_q       ( ),

	.sp_addr       ( ioctl_download ? 15'h7fff : sp_addr ),
	.sp_q          ( sp_do )
);

reg [15:0] cpu2_addr;

// ROM download controller
always @(posedge clk_sys) begin
	reg        ioctl_wr_last = 0;

	ioctl_wr_last <= ioctl_wr;
	if (ioctl_download) begin
		if (~ioctl_wr_last && ioctl_wr) begin
			port1_req <= ~port1_req;
			port2_req <= ~port2_req;
		end
	end
	// register for better timings
	//cpu2_addr <= ioctl_download ? 16'hffff : (16'h8000 + snd_addr[14:1]);
	cpu2_addr <= ioctl_download ? 16'hffff : {2'b10, snd_addr[14:1]};
end

// reset signal generation
reg reset = 1;
reg rom_loaded = 0;
always @(posedge clk_sys) begin
	reg ioctl_downloadD;
	reg [15:0] reset_count;
	ioctl_downloadD <= ioctl_download;

	// generate a second reset signal - needed for some reason
	if (RESET | status[0] | buttons[1] | ~rom_loaded) reset_count <= 16'hffff;
	else if (reset_count != 0) reset_count <= reset_count - 1'd1;

	if (ioctl_downloadD & ~ioctl_download) rom_loaded <= 1;
	reset <= RESET | status[0] | buttons[1] | ~rom_loaded | (reset_count == 16'h0001);
end

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fire1       <= pressed; // space
			'h014: btn_fire3       <= pressed; // ctrl

			'h005: btn_start_1     <= pressed; // F1
			'h006: btn_start_2     <= pressed; // F2
			'h004: btn_coin        <= pressed; // F3
			

			// JPAC/IPAC/MAME Style Codes
			'h02E: btn_coin        <= pressed; // 5
			'h036: btn_coin        <= pressed; // 6
			'h02D: btn_up          <= pressed; // R
			'h02B: btn_down        <= pressed; // F
			'h023: btn_left        <= pressed; // D
			'h034: btn_right       <= pressed; // G
			'h01C: btn_fire1       <= pressed; // A

			'h00D: btn_start_1          <= pressed; // TAB
			'h01A: btn_start_2       <= pressed; // Z
			'h012: btn_start_3       <= pressed; // shift left
			'h011: btn_start_4       <= pressed; // alt
		endcase
	end
end

wire [5:0] wheel1;
spinner spinner1 (
	.clock_40(clk_sys),
	.reset(reset),
	.btn_acc(),
	.btn_left(m_left),
	.btn_right(m_right),
	.ctc_zc_to_2(vs),
	.spin_angle(wheel1)
);

wire [5:0] wheel2;
spinner spinner2 (
	.clock_40(clk_sys),
	.reset(reset),
	.btn_acc(),
	.btn_left(m_left2),
	.btn_right(m_right2),
	.ctc_zc_to_2(vs),
	.spin_angle(wheel2)
);

wire [5:0] wheel3;
spinner spinner3 (
	.clock_40(clk_sys),
	.reset(reset),
	.btn_acc(),
	.btn_left(m_left3),
	.btn_right(m_right3),
	.ctc_zc_to_2(vs),
	.spin_angle(wheel3)
);

wire [5:0] wheel4;
spinner spinner4 (
	.clock_40(clk_sys),
	.reset(reset),
	.btn_acc(),
	.btn_left(m_left4),
	.btn_right(m_right4),
	.ctc_zc_to_2(vs),
	.spin_angle(wheel4)
);

reg btn_start_1 = 0;
reg btn_start_2 = 0;
reg btn_start_3 = 0;
reg btn_start_4 = 0;
	
reg btn_fire1 = 0;
reg btn_fire2 = 0;
reg btn_fire3 = 0;
reg btn_fire4 = 0;

reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_coin  = 0;

wire m_up     = btn_left  | joystick_0[3];
wire m_down   = btn_right | joystick_0[2];
wire m_left   = btn_down  | joystick_0[1];
wire m_right  = btn_up    | joystick_0[0];
wire m_fire1  = btn_fire1 | joystick_0[4];
wire m_fire1b = btn_fire2 | joystick_0[5];

wire m_up2     = joystick_1[3];
wire m_down2   = joystick_1[2];
wire m_left2   = joystick_1[1];
wire m_right2  = joystick_1[0];
wire m_fire2   = joystick_1[4];
wire m_fire2b  = joystick_1[5];

wire m_up3     = joystick_2[3];
wire m_down3   = joystick_2[2];
wire m_left3   = joystick_2[1];
wire m_right3  = joystick_2[0];
wire m_fire3   = joystick_2[4];
wire m_fire3b  = joystick_2[5];

wire m_up4     = joystick_3[3];
wire m_down4   = joystick_3[2];
wire m_left4   = joystick_3[1];
wire m_right4  = joystick_3[0];
wire m_fire4   = joystick_3[4];
wire m_fire4b  = joystick_3[5];

wire m_start_1 = btn_start_1 | joystick_0[6];
wire m_start_2 = btn_start_2 | joystick_1[6];
wire m_start_3 = btn_start_3 | joystick_2[6];
wire m_start_4 = btn_start_4 | joystick_3[6];
wire m_coin    = btn_coin | joystick_0[7] | joystick_1[7] | joystick_2[7] | joystick_3[7];

wire ce_pix_old;
wire hblank, vblank;
wire hs, vs;
wire [2:0] r,g;
wire [2:0] b;

//wire no_rotate = status[2] & ~direct_video;
reg ce_pix;
always @(posedge clk_sys) begin
        reg [2:0] div;

        div <= div + 1'd1;
        ce_pix <= !div;
end

// 512x480
arcade_fx #(512,9) arcade_video
(
	.*,

	.ce_pix(status[13] ? ce_pix_old: ce_pix),
	.clk_video(clk_sys),
	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[5:3])
);

assign AUDIO_S = 0;
//wire [15:0] audio_l, audio_r;

assign AUDIO_L = { audio, 5'd0 };
assign AUDIO_R = { audio, 5'd0 };

wire   players4 = status[8];
wire   difficulty = status[9];
wire   girl = status[10];


dderby dderby
(
	.clock_40(clk_sys),
	.reset(reset),
	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_vblank(vblank),
	.video_hblank(hblank),
	.video_hs(hs),
	.video_vs(vs),
	.video_ce(ce_pix_old),
	.tv15Khz_mode(~status[13]),
	//.separate_audio(1'b0),
	.separate_audio(status[12]),
	.audio_out(audio),
	.coin1(m_coin),
	.coin2(m_coin),
	.coin3(m_coin),
	.coin4(m_coin),
	
	.start4(m_start_4),
	.start3(m_start_3),
	.start2(m_start_2),
	.start1(m_start_1),
	
	.p1_fire1(m_fire1),
	.p1_fire2(m_fire1b),
	.p2_fire1(m_fire2),
	.p2_fire2(m_fire2b),
	.p3_fire1(m_fire3),
	.p3_fire2(m_fire3b),
	.p4_fire1(m_fire4),
	.p4_fire2(m_fire4b),

	.wheel1(wheel1),
	.wheel2(wheel2),
	.wheel3(wheel3),
	.wheel4(wheel4),
	
	.service(status[6]),
	.dipsw(~{3'b000, girl, 1'b0, difficulty, players4}), // NU, coins/credit, girl, free play, difficulty, 2player
	.cpu_rom_addr ( rom_addr ),
	.cpu_rom_do   ( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
	.snd_rom_addr ( snd_addr ),
	.snd_rom_do   ( snd_addr[0] ? snd_do[15:8] : snd_do[7:0] ),
	.sp_addr      ( sp_addr ),
	.sp_graphx32_do ( sp_do ),
	.dl_addr      ( dl_addr    ),
	.dl_wr        ( ioctl_wr   ),
	.dl_data      ( ioctl_dout )
);




endmodule
