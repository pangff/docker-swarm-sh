# docker swarm 一键生成 

要在本机机器安装docker-machine,安装方法 https://docs.docker.com/machine/install-machine/
根据需要修改conf/global.conf

* 环境配置,ENV=local本地环境，swarm在本机会通过virtualbox创建，所以确保本地有相关环境；EVN=remote,会通过create --driver generic创建远程节点，但是要保证conf/nodes.conf中配置好了远程节点的用户名和ip,格式为"用户名@ip"。例子中ENV=local，采用virtualbox方式。
```
ENV=local
```
* 全部节点数配置，NODE_COUNT=n，最终结果是创建swarm-1 ... swarm-n节点。例子全部节点数为3，会创建swarm-1、swarm-2、swarm-3节点
```
NODE_COUNT=3
```
* 初始化节点序号,在哪个节点作为初始manager节点，序号从1开始。如果是ENV是local那么序号就是1-NODE_COUNT任意，如果ENV是remote那么序号就从nodes.conf配置文件中找到一个节点。一般为了简单我们都从swarm-1的节点开始
```
INIT_SWAM_NODE_NUM=1
```
* manager节点序号,要作为manager的节点序号，要是奇数个原因参考官方文档，下面例子以swarm-1、swarm-2、swarm-3节点为manager

```
MANAGER_NODES_NUM=1,2,3
```

* worker节点序号,要作为worker的节点序号，注意不要和MANAGER_NODES_NUM中重复，因为一个节点要么是manager要么是worker，否则会创建出错，例子中没有worker节点

```
WOKER_NODES_NUM=
```

* ELK节点序号,我们最终目的是在swarm环境部署elk。ELK_NODES_NUM指明label=elk的节点序号，elk相关服务只会在label是elk节点部署，例子中以swarm-2的节点为elk节点。

```
ELK_NODES_NUM=2
```

* ELK节点数

```
ELK_NODE_COUNT=1
```
* ELK redis 管道服务数量

```
LOG_REDIS_COUNT=1
```
进入项目根目录执行下面命令创建
```
./scripts/dm-swarm.sh
```
# logspout-elk日志 一键部署
进入项目根目录，执行下面命令
```
./scripts/dm-swarm-service-elk.sh
```
