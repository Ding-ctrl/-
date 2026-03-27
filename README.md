# -
芯片设计ai

## VCS 混合语言编译指南（VHDL + Verilog + SystemVerilog）

本项目使用 Synopsys VCS 进行混合语言（VHDL、Verilog、SystemVerilog）编译仿真，生成 `simv` 可执行文件和 `simv.daidir` 调试目录。

### 目录结构

```
.
├── filelist/
│   ├── vhdl.f          # VHDL 源文件列表
│   ├── verilog.f       # Verilog 源文件列表
│   └── sv.f            # SystemVerilog 源文件列表
├── sim/
│   └── Makefile        # VCS 编译 Makefile
├── run_vcs.sh          # 一键编译脚本
└── README.md
```

### 快速开始

#### 方法一：使用 Makefile

```bash
cd sim
make compile    # 编译设计，生成 simv 和 simv.daidir
make run        # 运行仿真
make all        # 编译 + 运行
make clean      # 清理生成文件
make verdi      # 打开 Verdi 波形查看器
```

#### 方法二：使用脚本

```bash
./run_vcs.sh                    # 默认编译
./run_vcs.sh -top tb_top        # 指定顶层模块
./run_vcs.sh -run               # 编译并运行仿真
./run_vcs.sh -clean             # 清理文件
```

#### 方法三：手动执行 VCS 命令

**混合语言编译需要分步执行（三步分析 + 一步综合）：**

```bash
# Step 1: 分析 VHDL 文件（使用 vhdlan）
vhdlan -full64 -work WORK -f filelist/vhdl.f

# Step 2: 分析 Verilog 文件（使用 vlogan）
vlogan -full64 -work WORK -timescale=1ns/1ps -f filelist/verilog.f

# Step 3: 分析 SystemVerilog 文件（使用 vlogan -sverilog）
vlogan -full64 -work WORK -sverilog -timescale=1ns/1ps -f filelist/sv.f

# Step 4: VCS 综合编译（生成 simv 和 simv.daidir）
vcs -full64 -sverilog -debug_access+all -lca -kdb \
    -timescale=1ns/1ps +lint=TFIPC-L \
    -top tb_top -o simv -l compile.log tb_top
```

> **注意：** `simv.daidir` 是 VCS 自动生成的调试信息目录，与 `simv` 可执行文件一起产生，无需额外参数。添加 `-debug_access+all -kdb` 选项可确保生成完整的调试信息，支持 Verdi 打开波形。

**如果只有 Verilog 和 SystemVerilog（无 VHDL），可以使用单条命令：**

```bash
vcs -full64 -sverilog -debug_access+all -lca -kdb \
    -timescale=1ns/1ps +lint=TFIPC-L \
    -f filelist/verilog.f -f filelist/sv.f \
    -top tb_top -o simv -l compile.log
```

### 运行仿真

```bash
./simv -l run.log +fsdb+autoflush
```

### 使用 Verdi 查看波形

```bash
verdi -dbdir simv.daidir
```

### 关键 VCS 编译选项说明

| 选项 | 说明 |
|------|------|
| `-full64` | 64 位编译模式 |
| `-sverilog` | 启用 SystemVerilog 支持 |
| `-debug_access+all` | 开启完整调试访问（生成 `simv.daidir`） |
| `-lca` | 启用受限客户访问功能 |
| `-kdb` | 生成 Verdi KDB 数据库 |
| `-timescale=1ns/1ps` | 设置默认时间精度 |
| `-top <module>` | 指定顶层模块 |
| `-o simv` | 指定输出可执行文件名 |
| `-f <filelist>` | 指定源文件列表 |
| `-l compile.log` | 编译日志输出到文件 |
| `+lint=TFIPC-L` | 启用 lint 检查 |

### 文件列表使用方法

在 `filelist/` 目录下的 `.f` 文件中添加源文件路径（每行一个），支持注释（`#` 开头）：

```
# filelist/sv.f 示例
../rtl/pkg.sv
../rtl/interface.sv
../rtl/module_a.sv
../tb/tb_top.sv
```
