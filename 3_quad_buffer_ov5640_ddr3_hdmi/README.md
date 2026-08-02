# 四缓冲视频缓存架构设计

## 项目简介

为解决实时视频处理中“非就地处理”（算法需同时读取源帧、写入结果帧）带来的缓存管理难题，独立推导并设计了**四缓冲（Quad Buffer）架构**。该架构从理论上解决了经典三缓冲在此场景下的死锁问题，实现了采集、处理、显示三条流水线的完全解耦。已完成完整RTL设计与核心状态机编写。当前正进行空载测试验证，定位并解决AXI SmartConnect多主控访问时的数据同步问题。
### **视频缓存四缓存架构图**
![四缓冲核心架构图](./IMAGES/视频缓存项目（四缓.png)

## 架构设计

四个物理Buffer在逻辑上分为两组，物理与逻辑完全隔离：

-   **in_buf 组（两个Buffer）**：Camera写入，P模块读取。
-   **proc_buf 组（两个Buffer）**：P模块写入，HDMI读取。

P模块是两组之间的唯一桥梁：它从 `in_buf` 读取原始帧，处理后将结果写入 `proc_buf`。


## 当前状态与文件说明

## 文件说明
-   `RTL/`：核心 RTL 代码
### 四缓视频项目顶层文件
#### [四缓视频项目顶层](./RTL/camera_ddr3_hdmi/sources_1/top/ov5640_ddr3_hdmi.v)

### 摄像头初始化及数据捕获相关文件
#### [SCCB初始化顶层控制文件](./RTL/camera_ddr3_hdmi/sources_1/camera/sccb_master/sccb_master.v)
#### [IIC 基本操作产生模块](./RTL/camera_ddr3_hdmi/sources_1/camera/sccb_master/iic_bit_shift.v)
#### [IIC协议拼接](./RTL/camera_ddr3_hdmi/sources_1/camera/sccb_master/iic_control.v)
#### [OV5640摄像头初始化ROM表](./RTL/camera_ddr3_hdmi/sources_1/camera/sccb_master/ov5640_init_table_jpeg.v)
#### [OV5640摄像头初始化ROM表](./RTL/camera_ddr3_hdmi/sources_1/camera/sccb_master/ov5640_init_table_rgb.v)
#### [摄像头频率帧率监控】](./RTL/camera_ddr3_hdmi/sources_1/camera/camera_monitor.v)
#### [DVP接口转FIFO数据输入](./RTL/camera_ddr3_hdmi/sources_1/camera/dvp_capture.v)


### HDMI输出驱动
#### [HDMI输出顶层](./RTL/camera_ddr3_hdmi/sources_1/hdmi_over_dvi_driver/hdmi_driver.v)
#### [VGA转HDMI](./RTL/camera_ddr3_hdmi/sources_1/hdmi_over_dvi_driver/hdmi_over_dvi_encode.v)
#### [TMDS编码](./RTL/camera_ddr3_hdmi/sources_1/hdmi_over_dvi_driver/tmds_encode.v)
#### [VGA接口时序产生](./RTL/camera_ddr3_hdmi/sources_1/hdmi_over_dvi_driver/vga_ctrl.v)


### 缓冲切换控制及AXI4总线仲裁
#### [四缓冲切换逻辑](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/quad_buffer_ctrl.v)
#### [HDMI与P_r的读仲裁](.RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/arbitration/axi4_r_arbitration.v)
#### [CAMERA与P_w的写仲裁](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/arbitration/axi4_w_arbitration.v)



### 摄像头写入（W模块）
#### [W模块顶层](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/W_module/w_module_ctrl.v)
#### [W模块的fifo转AXI模块](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/W_module/cam_w_fifo_to_axi4.v)


### 基于Sobel算法的P模块（P模块）
#### [P模块顶层](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/p_module_ctrl.v)
#### [P模块的AXI4转FIFO模块](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/proc_r_axi4_to_fifo.v)
#### [模块的输入数据处理，添加HS/VS](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/pixel_count_request_ctrl.v)
#### [RGB转灰度](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/rgb_2_gray.v)
#### [基于RAM的三行像素移位缓存](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/image_line_shift_cache.v)
#### [sobel计算逻辑](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/sobel_calculate.v)
#### [灰度转RGB](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/gray_2_rgb.v)
#### [处理完数据写入控制模块](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/pixel_count_write_ctrl.v)
#### [P模块的fifo转AXI模块](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/P_module/proc_w_fifo_to_axi4.v)



### HDMI读取（R模块）
#### [R模块顶层](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/R_module/r_module_ctrl.v)
#### [R模块的AXI4转FIFO模块](./RTL/camera_ddr3_hdmi/sources_1/quad_buffer_ctrl/R_module/hdmi_r_axi4_to_fifo.v)


### 仿真文件
#### [仿真特制顶层](./RTL/camera_ddr3_hdmi/sources_1/top/ov5640_ddr3_hdmi_testbench.v)
#### [P模块仿真特制顶层](/RTL/camera_ddr3_hdmi/sources_1/new/p_module_ctrl_test.v)
#### [仿真文件](/RTL/camera_ddr3_hdmi/sim_1/ov5640_ddr3_hdmi_tb.v)
FIFO
### 约束文件
#### [00_pinout.xdc](./RTL/camera_ddr3_hdmi/constrs_1/00_pinout.xdc)
#### [01_clocks.xdc](./RTL/camera_ddr3_hdmi/constrs_1/01_clocks.xdc)
#### [02_input_output.xdc](./RTL/camera_ddr3_hdmi/constrs_1/02_input_output.xdc)
#### [03_cdc.xdc](./RTL/camera_ddr3_hdmi/constrs_1/03_cdc.xdc)
#### [04_exceptions.xdc](./RTL/camera_ddr3_hdmi/constrs_1/04_exceptions.xdc)

## Buffer 状态模型

每个Buffer在任意时刻处于三种互斥状态之一：

| 状态 | 含义 | 谁可以访问 |
|:---|:---|:---|
| **空闲** | 无有效数据，可被写入 | 生产者（Cam/P）可申请写入 |
| **就绪** | 生产者已写完，等待消费者取走 | 消费者（P/HDMI）可取走，生产者可覆盖 |
| **锁定** | 消费者正在使用，绝对不可覆盖 | 仅锁定它的消费者可释放 |


## 核心操作流程

![四缓冲切换流程](./IMAGES/四缓冲逻辑图.png)

## 速率组合分析

-   **Cam快，P慢**：Cam反复覆盖就绪 `in_buf`，P每次取最新。`proc_buf` 侧总有空闲，P不触发覆盖。
-   **P快，HDMI慢**：P快速产出结果，反复覆盖就绪 `proc_buf`，HDMI每次取最新。`in_buf` 侧总有空闲，Cam不触发覆盖。
-   **速率匹配**：退化为乒乓操作，从不覆盖。每帧都被处理、被显示。
-   **HDMI初始无帧**：HDMI输出初始画面或黑屏，由HDMI模块自身决定，不造成系统错误。

## 技术要点

-   **独立架构推导**：从“三缓冲在非就地处理下为何死锁”出发，推导出理论最小缓冲数公式，完成四缓冲设计。
-   **严谨的状态模型**：三种互斥状态覆盖所有生命周期，事件驱动状态转移，从根本上杜绝竞态条件。
-   **多主控互联**：基于AXI SmartConnect实现三个独立Master对单一DDR3的并发访问。
-   **多速率兼容**：自动适配Camera 30fps、HDMI 60fps的速率差异及P模块的可变处理速率。

## 调试与升级记录

### 测试目标

在集成完整的四缓冲控制器之前，先进行“空载测试”——只接入Camera写模块和HDMI读模块（不接入P模块），验证AXI SmartConnect多主控互联的基本通路是否正常。

### 测试现象

上板后画面花屏，具体表现为读到了DDR3空白区域（未写入有效数据的区域），呈现典型的“雪花屏”。但仔细观察，花屏画面之下仍有正常图像在显示，说明数据通路部分工作，只是读写地址或数据流存在错位。

### 问题定位

-   已排除：双缓冲切换逻辑（禁用双缓冲后问题依旧）
-   已排除：MIG DDR3控制器本身（此前纯RTL直连版本验证通过）
-   **初步定位**：问题出在 AXI SmartConnect 的配置或多主控数据同步上。SmartConnect在仲裁两个Master（Camera写、HDMI读）的并发请求时，可能存在地址映射、ID路由或响应通道的数据错位问题。此问题暂未解决，但不影响四缓冲控制器自身的逻辑正确性。


