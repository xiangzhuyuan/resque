

关于 Resque
======

Resque( 发音类似"rescue"), 是一个完全基于`Redis`为后端存储的类库, 用来处理后台任务的消息队列实现.
后台任务可以封装成为 Ruby 类或者模块, 只要他们响应` perform` 方法就好. 这样做的好处就是既有的类或者模块
可以很容易直线后台任务的转换, 或者轻松创建一个全新的类来完成任务.

而 Resque 实现也不是从无到有, 也是站在了巨人的肩膀上. 通过` DelayedJob` 得到启发.
具体有什么不同呢, 可以看下面的比较:

1. 通过一个 Ruby 类库来创建, 查询和处理任务
2. 通过 Rake 创建一个 worker 用来处理任务.
3. 同时附带一个基于 Sinatra的 web app, 用来监视队列, 任务还有 worker.

Resque 的 worker 可以部署到多台机器上. 同时支持优先级, 可以很弹性的控制内存使用. 同时针对 REE 的使用场景进行了优化!

Resque 的消息是可持久化的. 借助 redis 的原生支持, Resque 支持常量时间, 原子 push 和 pop. 而且消息内容可视化, 将任务可以简单的json 序列化存储.

通过借助 Sinatra 的 web app 可以轻松监视当前 worker 的状态. 同时提供一个简单地使用统计情况, 帮助你来跟踪错误.

Resque 目前支持 Ruby2.0.0及以上.


起源
--------
Resque 的起源, 以及设计初衷看这个博客: [the blog post][0].


概览
--------

Resque 允许你可以创建任务然后将他们放在 queue 里, 之后再将这些任务拿来处理.
而这里说到的 `Resque 的任务`其实就是指能够响应` perform` 方法的 ruby 类或者模块, 看例子:


```ruby
class Archive
  @queue = :file_serve

  def self.perform(repo_id, branch = 'master')
    repo = Repository.find(repo_id)
    repo.create_archive(branch)
  end
end
```
这里的`@queue` 类实例变量用来决定将消息存贮到那个 queue 里. 实际上 queue 的名字是在允许时创建的. 你可以随意创建,而且不会有什么数量的限制. 而上面的意思就是将 Archive 的任务存储到` file_server` 这个 queue 里. 然后具体是怎么讲数据存进去呢?
看下面:


```ruby
class Repository
  def async_create_archive(branch)
    Resque.enqueue(Archive, self.id, branch)
  end
end
```
就像上面的例子一样, 通过 `repo.async_create_archive('masterbrew')` 就可以创建一个` file_server` 的 queue, 然后将这个 repository 存储到 queue 里.

然后这么读取这个消息而且处理它呢?

```ruby
klass, args = Resque.reserve(:file_serve)
klass.perform(*args) if klass.respond_to? :perform
```

上面的代码会'翻译'成这样:

```ruby
Archive.perform(44, 'masterbrew')
```
接着, 我们启动一个 worker, 来处理这个 job:

    $ cd app_root
    $ QUEUE=file_serve rake resque:work


这个就会创建一个 Resque 的 worker, 然后告诉它去从` file_server`queue 拿到消息进行处理. 接着就会通过` Resque.reserve` 来监视这个 queue, 当没有消息的时候就会休息. worker 是可以作用到多个 queue 的. 而且可以在多个机器上工作.事实上只要能够理解到 redis server 哪里无所谓.

任务
----
我们来说说什么样的任务需要在后台执行呢? 答案很简单, 只要花时间的就可以放到后台任务里取. 如很慢的插入的命令,磁盘维护, 数据处理等等.

在 github 里我们通常都是将下面的任务放在后台处理:

* Warming caches
* Counting disk usage
* Building tarballs
* Building Rubygems
* Firing off web hooks
* Creating events in the db and pre-caching them
* Building graphs
* Deleting users
* Updating our search index

这样我们就有了大大小小的35种后台任务.
不过这里有一点需要说明的就是并不是 web 程序就需要用到 Resque 这样的消息处理系统来辅助, 我们在这里只讲前台任务和后台任务. 因为这是一种概念上的不同.任何感觉耗时间拖慢系统的操作都是可以扔到 queue 里的后台处理.


### 持久化

Resque 里的任务都是在 Json 序列化之后存储起来的, 拿上面 *Archive*的例子, 我们将会这样创建任务:

```ruby
repo = Repository.find(44)
repo.async_create_archive('masterbrew')
```

而实际存储起来的任务在`file_serve` queue里是这样的:

```javascript
{
    'class': 'Archive',
    'args': [ 44, 'masterbrew' ]
}
```
因为需要存储的内容将要 json 序列化, 所以我们的参数一定要可序列化:
我们将要把它

```ruby
Resque.enqueue(Archive, self, branch)
```

替换成这样:

```ruby
Resque.enqueue(Archive, self.id, branch)
```

这也是我们为什么在代码库里的demo 代码中使用对象的 id 来作为参数使用来包裹对象.
因为这样就相比直接 把对象给 marshled了然后直接存储起来方便了很多.而且还有一个小的优点就是每当在执行任务的时候都是拿到最新的对象版本, 因为往往他们都是需要从 DB 或者 cache 里取到.

而如果直接把序列的对象给存储了完了拿来直接用,这样就有可能对象本身已经是过时的版本了.



### send_later / async


希望能够看到如` DelayedJob` 的` send_later`或者同样的功能, 通过使用实例方法而不是 job 的方法, 看看` examples/` 下面的代码. 在将来的版本里希望能够提供` async` 的功能.





### Failure

如果一个任务失败了怎么办? 它将会被记录下来,然后出发` Resque::Failure` 模块,
这些异常会通过 redis 或者其他不同的后台任务来处理. 在开发阶段可以通过` VERBOSE` 的环境变量来查看 log.

例如, Resque 是支持 Airbrake 的, 通过初始化文件或者 rake job 来配置它:

```ruby
# send errors which occur in background jobs to redis and airbrake
require 'resque/failure/multiple'
require 'resque/failure/redis'
require 'resque/failure/airbrake'

Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::Airbrake]
Resque::Failure.backend = Resque::Failure::Multiple
```

记住一点就是, 当你在任务里添加任何东西的时候, 你可能要抛出一些异常,你不能够想当然按顺序的扔出一些东西来 debug.


Workers
-------

对于 Resque 的 worker 来说,它是 rake 的 task 存在, 它一直存在, 它长这样子:

```ruby
start
loop do
  if job = reserve
    job.process
  else
    sleep 5 # Polling frequency = 5
  end
end
shutdown
```

启动一个 worker, 很简单:

    $ QUEUE=file_serve rake resque:work



默认的是 Resque 并不知道你的应用长什么, 用什么变量在跑,也就是说, 你需要将应用加载到 memory 里!

如果你将 Resque 作为一个插件安装到 Rails里, 我们可以这样来启动 worker: 从 rails 的根目录:

    $ QUEUE=file_serve rake environment resque:work

这将会记载环境变量在启动 worker 之前, 或者另外一种方法就是可以在` Resque::setup` 方法里添加初始化的依赖环境变量:


```ruby
task "resque:setup" => :environment
```

如这样的, 可以在启动初始化的时候这是 git 的超时时间:

```ruby
task "resque:setup" => :environment do
  Grit::Git.git_timeout = 10.minutes
end
```
这样做的好处就是我们可能在 web app 里并不会给它这样一个大的值, 但是我们的后台任务里它是可以接受的.


### Logging

worker 支持基本的 log 输出, 你可以通过这两个环境变量来设置 log 的详细程度:

- `VERBOSE` 
- `VVERBOSE` (very verbose) 

    $ VVERBOSE=1 QUEUE=file_serve rake environment resque:work

如果配合 rails 使用, 你可以在 rails实例化过程中这样设置:

```ruby
# config/initializers/resque.rb
Resque.logger = Logger.new(Rails.root.join('log', "#{Rails.env}_resque.log"))
```

### Process IDs (PIDs)

有很多时候记录下 Resque 的 worker 的进程 ID 是非常有用的, 我们可以通过` PIDFILE` 选项来轻松访问 PID:

    $ PIDFILE=./resque.pid QUEUE=file_serve rake environment resque:work

### Running in the background

有时候直接吧 worker 当在后台运行也是不错的,特别是配合 pidfile 一起使用更加是棒棒哒. 通过` BACKGROUND` 参数就能够轻松搞定:

    $ PIDFILE=./resque.pid BACKGROUND=yes QUEUE=file_serve \
        rake environment resque:work

### Polling frequency

可以通过` INTERVAL` 变量来控制 worker 从 redis 哪里抽取数据的频率:

    $ INTERVAL=0.1 QUEUE=file_serve rake environment resque:work

### Priorities and Queue Lists

Resque 是不支持通过数字来指定任务的优先级的, 不过通过 redis 的先进先出特定,可以控制 queu 的顺序来实现.
我们将这个控制优先级的 queue 序列称之为` queue list`.

例如我们手里同时又两个 queue, 一个` warm_cache`,另外还有` file_server`, 我们在启动这个 worker 的时候可以通过
指定 queue 的顺序来实现 queue 的优先级的功能:

    $ QUEUES=file_serve,warm_cache rake resque:work

当以这样的方式启动了 worker 之后, worker 会首先从` file_server` 来试图获取消息,如果有就会一直处理知道没有新的消息进来,
然后去查看` warm_cache`queue, 然后处理一条之后, 就会去查看` file_server`, 然后处理 file_server 知道没有新的, 如此循环.

通过这样的方式就能够实现 queue 的优先级, 在 github 我们可能通过如下的方式启动 worker:

    $ QUEUES=critical,archive,high,low rake resque:work
    $ QUEUES=critical,high,low rake resque:work


### Running All Queues

一个 worker 对应所有的 queue, 可以这样: 

    $ QUEUE=* rake resque:work

这样的写法, 实际在获取到的所有的 queue 之后, 是通过字母顺序排列优先级的.


### Running Multiple Workers

At GitHub we use god to start and stop multiple workers. A sample god
configuration file is included under `examples/god`. We recommend this
method.

在 Github 的实际实践当中,我们使用` god` 来完成启动和停止多 worker, 关于`god` 的使用可以查看` examples/god` 来了解.
而且我们也推荐这样的方式. 
如果你想要在开发模式下启动多 worker 的话,可以这样:


    $ COUNT=5 QUEUE=* rake resque:workers

这样将会创建5个单独的进程, 通过` ctrl-c`就可以完成停止这些 worker.

### Forking

On certain platforms, when a Resque worker reserves a job it
immediately forks a child process. The child processes the job then
exits. When the child has exited successfully, the worker reserves
another job and repeats the process.


在大部分的平台上, 当一个 worker 接受到一个 job 之后, 通常都是会` fork` 出一个子进程, 然后这个子进程会负责处理这个 job, 成功完成就直接退出.
这样反复执行. 为什么呢?


因为 Resque 假象总是会出现很混乱的场景.
为什么会有 Resque 的出现, 为什么会后台执行,归根结底出发点都是因为这些任务通常都是需要时间, 甚至会出错, 各种各样的结果就是
总是会出现异常的情况, 这样就很难直接拿 worker 的进程本身来处理这些 job, 加入一个任务花费了很多的内存, 然后你就告诉它
结束了这个任务就退出吧, 然后也是正常顺利进行了, 然后重新启动它, 加载了整个 app 的环境, 这个过程无非还是增加了很多的无用的 cpu 消耗.

甚至, 如果因为它消耗了很多内存, 它直接都不会响应这个停止或者重启的信号, 怎么办?

这就是为什么 Resque 它采用的`父/子进程模型`的设计.来保证每一个 job 都能够让一个 worker 来全心全意服务.(女仆跪)
假如一个 job 消耗了很多的内存, 当它完成之后就会释放出这些内存, 而不是继续接新的 job 来恶化这个循环.

假如一个 job 执行花了很长的时间, 就需要`kill` 掉它, 然后重启它, 而通过 Resque 的`父子进程`架构的设计,
可以完全通过父进程来杀掉这个耗时的子进程. 然后很容易的创建一个新的子进程, 没有浪费新的 cpu 消耗和延迟.

而且通过`父子进程`的设计, 我们监控起来也是很容易, 每当杀掉或者重启父进程, 如果没有子进程存在,我们就需要更新当前的监控进程 list,
而使用了父进程, 我们不需要来更新父进程, 因为我们根本没有动父进程.

### 来看看 Parents and Children

通过下面的方法可以来查看当前父子进程之间的关系:

    $ ps -e -o pid,command | grep [r]esque
    92099 resque: Forked 92102 at 1253142769
    92102 resque: Processing file_serve since 1253142769
可以很容易看出`92099	`fork 出了子进程`92102`, 而`92102`已经开始工作了.
(有时候我们完全可以通过我们 since 开始的时间来杀掉那些已经不新鲜的子进程)

我们还可以拿到当主进程休息的时候,它当前正在监视那个 queue:

    $ ps -e -o pid,command | grep [r]esque
    92099 resque: Waiting for file_serve,warm_cache


### Signals

Resque 内置了一些信号量, 用来处理父进程:

* `QUIT` - Wait for child to finish processing then exit
* `TERM` / `INT` - Immediately kill child then exit
* `USR1` - Immediately kill child but don't exit
* `USR2` - Don't start to process any new jobs
* `CONT` - Start to process new jobs again after a USR2

如果你想要优雅的杀掉 worker进程, 请使用` QUIT`.

如果你指向想要杀掉坏了子进程, 可以通过` USR1`, 这样子进程也是会执行完当前的任务处理, 
而如果遇到找不到当前子进程的情况时, Resque 会认为当前父进程都已经坏掉了, 会直接踢掉父进程,

如果你想要直接杀掉坏死的子进程, 直接给它`TERM`指令就好.
而如果想要停止一个正在执行的 job, 但是又想要保留当前执行的状态,(举例,临时缓解加载负荷, 通过` USR2`来停止这个进程,之后通过` CONT` 里启动它.


#### Heroku 平台上又是如何使用信号的呢?

对于 heroku 来说, 每次执行停止命令都是发送` TERM` 指令到每一个进程, 这样也就引发了`Resque::TermException` 错误.
但是对于执行时间较短的进程, 可以给一些时间然后再来停止这些进程.为了达到这个目的, 可以这样来设置变量:

* `RESQUE_PRE_SHUTDOWN_TIMEOUT` - 这个变量就是可以告诉父进程当接受到` TERM` 指令后多久来杀死子进程.
* `TERM_CHILD` - 同时需要配和使用这个变量, 来和  `RESQUE_PRE_SHUTDOWN_TIMEOUT`一起使用.当到达超时间却还没有杀掉子进程就会报这个 `Resque::TermException` 并退出.

* `RESQUE_TERM_TIMEOUT` - 默认的情况你可以有时间来在 job 里处理`Resque::TermException` . `RESQUE_TERM_TIMEOUT`和`RESQUE_PRE_SHUTDOWN_TIMEOUT` 需要小于 heroku 上的这个值. [heroku dyno timeout](https://devcenter.heroku.com/articles/limits#exit-timeout).



略...

前端页面
-------------

Resque 同时搭载了一个基于 sinatra 的 web app, 它可以用来监视当前 Resque 的运行状态.

![The Front End](https://camo.githubusercontent.com/64d150a243987ffbc33f588bd6d7722a0bb8d69a/687474703a2f2f7475746f7269616c732e6a756d7073746172746c61622e636f6d2f696d616765732f7265737175655f6f766572766965772e706e67)

### 独立运行

如果你是通过 gem 的形式安装了 Resque, 这样就很容易执行它了:
    $ resque-web

因为它是基于 rack 的 app, 所以常用的一些参数都是可以的, 如指定端口:

    $ resque-web -p 8282

同样还可以指定一个完整的配置文件, 但是需要注意的就是它应该是最后一个参数:

    $ resque-web -p 8282 rails_root/config/initializers/resque.rb

同样基于 sinatra 的约定, 直接通过`- N` 就可以给 app 一个命名空间:

    $ resque-web -p 8282 -N myapp

通过`- r` 就可以指定一个非默认的 redis 连接:

    $ resque-web -p 8282 -r localhost:6379:2



安装 Resque
-----------------

### 在 Rack 系的 app 里, 作为一个 gem 使用

    $ gem install resque

然后直接在 app 里引用:

``` ruby
require 'resque'
```
然后启动 app

    rackup config.ru

这样就可以在 app 里直接使用 Resque 了, 如果需要启动 worker, 可以在根目录创建一个` Rackfile`, 或者在现有的 Rackfile 里添加下面的代码:

``` ruby
require 'your/app'
require 'resque/tasks'
```

如果使用 Rails5, 需要在这个文件`lib/tasks/resque.rb`添加下面的代码:

```ruby
require 'resque/tasks'
task 'resque:setup' => :environment
```

之后就可以启动 worker 了:

    $ QUEUE=* rake resque:work

或者你可以直接在 Rackfile 里添加一个 setup
的 hook, 这样可以避免每次加载 app:


### In a Rails 3.x or 4.x app, as a gem

作为 gem 使用, 添加引用到 Gemfile:


    $ cat Gemfile
    ...
    gem 'resque'
    ...

bundle

    $ bundle install

启动 rails

    $ rails server

That's it! You can now create Resque jobs from within your app.

To start a worker, add this to a file in `lib/tasks` (ex:
`lib/tasks/resque.rake`):

``` ruby
require 'resque/tasks'
```

Now:

    $ QUEUE=* rake environment resque:work

Don't forget you can define a `resque:setup` hook in
`lib/tasks/whatever.rake` that loads the `environment` task every time.


Configuration
-------------

You may want to change the Redis host and port Resque connects to, or
set various other options at startup.

Resque has a `redis` setter which can be given a string or a Redis
object. This means if you're already using Redis in your app, Resque
can re-use the existing connection.

String: `Resque.redis = 'localhost:6379'`

Redis: `Resque.redis = $redis`

For our rails app we have a `config/initializers/resque.rb` file where
we load `config/resque.yml` by hand and set the Redis information
appropriately.

Here's our `config/resque.yml`:

    development: localhost:6379
    test: localhost:6379
    staging: redis1.se.github.com:6379
    fi: localhost:6379
    production: redis1.ae.github.com:6379

And our initializer:

``` ruby
rails_root = ENV['RAILS_ROOT'] || File.dirname(__FILE__) + '/../..'
rails_env = ENV['RAILS_ENV'] || 'development'

resque_config = YAML.load_file(rails_root + '/config/resque.yml')
Resque.redis = resque_config[rails_env]
```

Easy peasy! Why not just use `RAILS_ROOT` and `RAILS_ENV`? Because
this way we can tell our Sinatra app about the config file:

    $ RAILS_ENV=production resque-web rails_root/config/initializers/resque.rb

Now everyone is on the same page.

Also, you could disable jobs queueing by setting 'inline' attribute.
For example, if you want to run all jobs in the same process for cucumber, try:

``` ruby
Resque.inline = ENV['RAILS_ENV'] == "cucumber"
```


Plugins and Hooks
-----------------

For a list of available plugins see
<http://wiki.github.com/resque/resque/plugins>.

If you'd like to write your own plugin, or want to customize Resque
using hooks (such as `Resque.after_fork`), see
[docs/HOOKS.md](http://github.com/resque/resque/blob/master/docs/HOOKS.md).


Namespaces
----------

If you're running multiple, separate instances of Resque you may want
to namespace the keyspaces so they do not overlap. This is not unlike
the approach taken by many memcached clients.

This feature is provided by the [redis-namespace][rs] library, which
Resque uses by default to separate the keys it manages from other keys
in your Redis server.

Simply use the `Resque.redis.namespace` accessor:

``` ruby
Resque.redis.namespace = "resque:GitHub"
```

We recommend sticking this in your initializer somewhere after Redis
is configured.


Demo
----

Resque ships with a demo Sinatra app for creating jobs that are later
processed in the background.

Try it out by looking at the README, found at `examples/demo/README.markdown`.


Monitoring
----------

### god

If you're using god to monitor Resque, we have provided example
configs in `examples/god/`. One is for starting / stopping workers,
the other is for killing workers that have been running too long.

### monit

If you're using monit, `examples/monit/resque.monit` is provided free
of charge. This is **not** used by GitHub in production, so please
send patches for any tweaks or improvements you can make to it.


Questions
---------

Please add them to the [FAQ](https://github.com/resque/resque/wiki/FAQ) or open an issue on this repo.


Development
-----------

Want to hack on Resque?

First clone the repo and run the tests:

    git clone git://github.com/resque/resque.git
    cd resque
    rake test

If the tests do not pass make sure you have Redis installed
correctly (though we make an effort to tell you if we feel this is the
case). The tests attempt to start an isolated instance of Redis to
run against.

Also make sure you've installed all the dependencies correctly. For
example, try loading the `redis-namespace` gem after you've installed
it:

    $ irb
    >> require 'rubygems'
    => true
    >> require 'redis/namespace'
    => true

If you get an error requiring any of the dependencies, you may have
failed to install them or be seeing load path issues.


Contributing
------------

Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

Once you've made your great commits:

1. [Fork][1] Resque
2. Create a topic branch - `git checkout -b my_branch`
3. Push to your branch - `git push origin my_branch`
4. Create a [Pull Request](http://help.github.com/pull-requests/) from your branch
5. That's it!


Mailing List
------------

This mailing list is no longer maintained. The archive can be found at <http://librelist.com/browser/resque/>.


Meta
----

* Code: `git clone git://github.com/resque/resque.git`
* Home: <http://github.com/resque/resque>
* Docs: <http://rubydoc.info/gems/resque>
* Bugs: <http://github.com/resque/resque/issues>
* List: <resque@librelist.com>
* Chat: <irc://irc.freenode.net/resque>
* Gems: <http://gemcutter.org/gems/resque>

This project uses [Semantic Versioning][sv].


Author
------

Chris Wanstrath :: chris@ozmm.org :: @defunkt

[0]: http://github.com/blog/542-introducing-resque
[1]: http://help.github.com/forking/
[2]: http://github.com/resque/resque/issues
[sv]: http://semver.org/
[rs]: http://github.com/resque/redis-namespace
[cb]: http://wiki.github.com/resque/resque/contributing


