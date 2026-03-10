
1.拓扑：发端和接收端服务器，tofino2充当源端和目的端的tor
服务器A ──(136)── [Switch] ──(192, 193, 194, 195, 184, 185, 186, 187)── [一对一光纤连接] ──(312, 313, 314, 315, 320, 321, 322, 323)── [Switch] ──(304)── 服务器B
                   源端ToR                                                         目的端ToR
2. ECMP组更新
源  端tor ECMP组中的[192,193]替换为[168,169]
目的端tor ECMP组中的[312,313]替换为[296,297]
[168,169]到[296,297]也是有一对一的光纤连接

3. 对比实验：
无保护（pod2pod）：
  T0: 发流 ─────────────────────────┐
  T_trigger: 直接更新 ECMP group    │──> 乱序，FCT 变大
  T_end: 统计 FCT
实验步骤：
（1）在交换机数据面启动pod2pod程序：root@localhost:/sde/bf-sde-9.7.1# ./run_switchd.sh -p pod2pod --arch tf2
（2）在交换机控制面启动端口up：root@localhost:/sde/bf-sde-9.7.1# ./run_bfshell.sh -b home/xxx/set_up/forward_set_up.py 
（3）在交换机控制面下发流表：root@localhost:/sde/bf-sde-9.7.1# ./run_p4_tests.sh -p pod2pod -t home/xxx/pod2pod/
（4）在server b上启动接收：sudo ./rdma_receiver   --dev mlx5_1   --ib-port 1   --gid-idx 3   --port 18512   --recv-buf 1024
（5）在server a上启动发送：./rdma_sender   --dev mlx5_1   --ib-port 1   --gid-idx 3   --server 192.168.41.2   --port 18512   --trace /home/xxx/traffic_gen/test_solar2022_20G_n4_t0.5_L0.2.txt  --output solar_INR_20G_n4_t0.5_60load_fct.csv   --send-buf 1024   --inline 0
有保护（dfmv2）：
  T0: 发流 ─────────────────────────┐
  T_trigger:
    1. 写 reg_migration_state = 1   │
    2. sleep 1ms                    │──> DFM 保护，FCT 正常
    3. 更新 ECMP group              │
  T_end: 统计 FCT（CLEAR 后自动清除迁移状态）
实验步骤：
（1）在交换机数据面启动pod2pod程序：root@localhost:/sde/bf-sde-9.7.1# ./run_switchd.sh -p dfmv2 --arch tf2
（2）在交换机控制面启动端口up：root@localhost:/sde/bf-sde-9.7.1# ./run_bfshell.sh -b home/xxx/set_up/forward_set_up.py 
（3）在交换机控制面下发流表：root@localhost:/sde/bf-sde-9.7.1# ./run_p4_tests.sh -p dfmv2 -t home/xxx/dfmv2/
（4）在server b上启动接收：sudo ./rdma_receiver   --dev mlx5_1   --ib-port 1   --gid-idx 3   --port 18512   --recv-buf 1024
（5）在server a上启动发送：./rdma_sender   --dev mlx5_1   --ib-port 1   --gid-idx 3   --server 192.168.41.2   --port 18512   --trace /home/xxx/traffic_gen/test_solar2022_20G_n4_t0.5_L0.2.txt  --output solar_INR_20G_n4_t0.5_60load_fct.csv   --send-buf 1024   --inline 0