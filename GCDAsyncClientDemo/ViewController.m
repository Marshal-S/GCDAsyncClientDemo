//
//  ViewController.m
//  GCDAsyncClientDemo
//
//  Created by Marshal on 2021/5/24.
//

#import "ViewController.h"
#import <CocoaAsyncSocket/GCDAsyncSocket.h>

@interface ViewController ()<GCDAsyncSocketDelegate>

@property (nonatomic, strong) GCDAsyncSocket *socket; //客户端的socket对象

@property (weak, nonatomic) IBOutlet UITextField *tfSendMessage;

@property (nonatomic, strong) NSMutableData *reciveData; //处理拆包逻辑专用

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initClientSocket];
}

- (void)initClientSocket {
    self.reciveData = [NSMutableData data];
    
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    
    NSError *error;
    //开启接收服务器，改成连接的服务器的ip地址，如果是在自己电脑开启的server，那就是自己电脑的ip地址
    [self.socket connectToHost:@"192.168.1.1" onPort:8040 withTimeout:-1 error:&error];
    if (error) {
        NSLog(@"连接服务器失败:%@",error.localizedDescription);
    }
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(nonnull NSString *)host port:(uint16_t)port {
    NSLog(@"连接服务器成功");
    //需要开启读取数据监听
    [sock readDataWithTimeout:-1 tag:10086];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    NSLog(@"断开了与服务器的连接");
}

//接收到服务端的数据
//消息结构 数据长度 + 数据类型 + 数据，需要解决粘包和拆包的问题
//处理粘包拆包逻辑的代码，在最底下
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSLog(@"-------------接收到了数据:%ld-----------", tag);
    [self reciveData:data]; //处理粘包逻辑代码,使用起来服务器和客户端，更为简单
//    [self reciveMoreData:data]; //处理同时存在粘包拆包逻辑,只处理粘包逻辑的
    //读取完毕数据之后，缓存区断开，需要重新监听
    [sock readDataWithTimeout:-1 tag:10086];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"发送消息成功");
}

//发送消息，发送消息的过程中如论如何必须保证包有序的进行传输，即：传输A、B、C三个数据，由于某种情况延缓了数据读取,可能出现A、BC的方式接收到数据，因此会出现粘包拆包的过程
//消息结构 数据长度 + 数据类型 + 数据(自己也可以加上发送时间之类的，可以根据实际场景定制)
//如果一个数据较长(视频),可以分为几段传递，那么还需要将内容粘到一起，因此：数据总长度 + 当前数据段长度 + 数据类型 + 数据
//数据分段传输的较大数据，需要多添加异步长度判断，内容拼接逻辑，这里就不多介绍了，切记传递文件需要按照顺序传递，否则会增加解析逻辑
//实际推荐视频、大图片走文件传输线路放到文件服务器，socket单个socket负责传输视频或者图片url即可，这样可以避免大文件信息堆积严重
- (IBAction)onClickToSendMessage:(id)sender {
    [self sendData];
//    [self sendMoreData];
}

#pragma mark --处理发送消息逻辑
//发送完整包的数据
- (void)sendData {
    NSMutableData *mData = [NSMutableData data];
    if (self.tfSendMessage.text.length > 0) {
        //给没个客户端发送一段数据
        const char *textStr = self.tfSendMessage.text.UTF8String;
        NSData *data = [NSData dataWithBytes:textStr length:strlen(textStr)];
        
        unsigned long dataLength = data.length;
        NSData *lenData = [NSData dataWithBytes:&dataLength length:8];
        [mData appendData:lenData];
        
        //文字类型
        unsigned int typeByte = 0x00000001;
        NSData *typeData = [NSData dataWithBytes:&typeByte length:4];
        [mData appendData:typeData];
        
        [mData appendData:data];
        NSLog(@"发送内容为：%@", self.tfSendMessage.text);
        self.tfSendMessage.text = @"";
    }else {
        //发送图片,其实实际上不一定在非要传递图片的，有的走的是http上传到文件服务器,然后利用返回的url在发送给对方
        NSData *imgData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"MMGG" ofType:@"jpeg"]];
        
        //展示发送的图片4s
        [self showImageInfo:imgData];
        
        //发送图片
        unsigned long dataLength = imgData.length;
        NSData *lenData = [NSData dataWithBytes:&dataLength length:8];
        [mData appendData:lenData];
        
        //图片类型
        unsigned int typeByte = 0x00000002;
        NSData *typeData = [NSData dataWithBytes:&typeByte length:4];
        [mData appendData:typeData];
        
        [mData appendData:imgData];
    }
    //发送消息
    [self.socket writeData:mData withTimeout:-1 tag:10086];
}

//发送可以分段的数据格式
- (void)sendMoreData {
    NSMutableData *mData = nil;
    if (self.tfSendMessage.text.length > 0) {
        mData = [NSMutableData data];
        //给没个客户端发送一段数据
        const char *textStr = self.tfSendMessage.text.UTF8String;
        NSData *data = [NSData dataWithBytes:textStr length:strlen(textStr)];
        
        unsigned long dataLength = data.length;
        NSData *tolLenData = [NSData dataWithBytes:&dataLength length:8];
        [mData appendData:tolLenData];
        
        unsigned long length = data.length;
        NSData *lenData = [NSData dataWithBytes:&length length:8];
        [mData appendData:lenData];
        
        //文字类型
        unsigned int typeByte = 0x00000001;
        NSData *typeData = [NSData dataWithBytes:&typeByte length:4];
        [mData appendData:typeData];
        
        [mData appendData:data];
        NSLog(@"发送内容为：%@", self.tfSendMessage.text);
        self.tfSendMessage.text = @"";
        //发送消息
        [self.socket writeData:mData withTimeout:-1 tag:10086];
    }else {
        //发送图片,其实实际上不一定在非要传递图片的，有的走的是http上传到文件服务器,然后利用返回的url在发送给对方
        NSData *imgData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"MMGG" ofType:@"jpeg"]];
        
        //展示发送的图片4s
        [self showImageInfo:imgData];
        
        //分段发送图片
        unsigned long dataLength = imgData.length;
        NSData *tolLenData = [NSData dataWithBytes:&dataLength length:8];
        unsigned currentIndex = 0;
        do {
            mData = [NSMutableData data];
            //开头追加总长度
            [mData appendData:tolLenData];
            
            unsigned long length = dataLength > 1000 ? 1000 : dataLength;
            dataLength -= length; //减少长度
            
            //加入当前数据段长度
            NSData *lenData = [NSData dataWithBytes:&length length:8];
            [mData appendData:lenData];
            
            //图片类型
            unsigned int typeByte = 0x00000002;
            NSData *typeData = [NSData dataWithBytes:&typeByte length:4];
            [mData appendData:typeData];
            
            [mData appendData:[imgData subdataWithRange:NSMakeRange(currentIndex, length)]];
            //发送消息
            [self.socket writeData:mData withTimeout:-1 tag:10086];
            
            currentIndex += length; //设置下一个节点索引
        } while (dataLength > 0);
    }
}


#pragma mark --处理粘包拆包逻辑
//处理粘包逻过程
- (void)reciveData:(NSData *)data {
    if (data.length < 1) return;
    
    //当前接收的数据包长度
    unsigned long totolLength = data.length;
    unsigned long currentLength = 0;
    //do while解决粘包问题，在里面进行拆包
    do {
        unsigned long length;
        unsigned int type;
        [data getBytes:&length range:NSMakeRange(currentLength, 8)];
        [data getBytes:&type range:NSMakeRange(currentLength + 8, 4)];
        //获取实际数据
        NSData *contentData = [data subdataWithRange:NSMakeRange(currentLength + 12, length)];
        
        if (type == 1) {
            //文字
            NSString *content = [[NSString alloc] initWithData:contentData encoding:NSUTF8StringEncoding];
            NSLog(@"接收的数据为:%@", content);
        }else if (type == 2) {
            //图片
            [self showImageInfo:contentData];
        }else {
            NSLog(@"不支持的数据类型");
        }
        currentLength += length + 12;
    } while (currentLength < totolLength);
}

//同时处理粘包拆包逻辑，只处理粘包逻辑的，这个也同样适用，这个总长度为数据的总长度，不计算前面的
- (void)reciveMoreData:(NSData *)data {
    if (data.length < 1) return;
    
    //当前接收的数据包长度
    unsigned long totolLength = data.length;
    unsigned long currentLength = 0;
    //do while解决粘包问题，在里面进行拆包
    do {
        //处理粘包逻辑
        unsigned long datalength; //数据总长度
        unsigned long length; //当前数据包长度
        unsigned int type; //数据类型
        [data getBytes:&datalength range:NSMakeRange(currentLength, 8)];
        [data getBytes:&length range:NSMakeRange(currentLength + 8, 8)];
        [data getBytes:&type range:NSMakeRange(currentLength + 16, 4)];
        //获取实际数据
        NSData *contentData = [data subdataWithRange:NSMakeRange(currentLength + 20, length)];
        
        currentLength += length + 20;
        
        //处理拆包逻辑
        if (self.reciveData.length < totolLength) {
            [self.reciveData appendData: contentData];
        }
        unsigned long reciveLength = self.reciveData.length;
        if (reciveLength  == datalength) {
            if (type == 1) {
                //文字
                NSString *content = [[NSString alloc] initWithData:self.reciveData encoding:NSUTF8StringEncoding];
                NSLog(@"接收的数据为:%@", content);
            }else if (type == 2) {
                //图片
                [self showImageInfo:self.reciveData];
            }else {
                NSLog(@"不支持的数据类型");
            }
            self.reciveData = [NSMutableData data]; //重新初始化
        }else if (reciveLength > datalength) {
            NSLog(@"数据传输或解析出现错误");
            return;
        }
    } while (currentLength < totolLength);
}

- (IBAction)onClickToDisconnect:(id)sender {
    [self.socket disconnect];
    self.socket = nil;
}

//展示接收的图片
- (void)showImageInfo:(NSData *)imgData {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImageView *ivImage = [[UIImageView alloc] initWithImage:[UIImage imageWithData:imgData]];
        ivImage.frame = CGRectMake(20, 300, 300, 300);
        [self.view addSubview:ivImage];
        
        ivImage.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.1, 0.1);
        [UIView animateWithDuration:2 animations:^{
            ivImage.transform = CGAffineTransformScale(CGAffineTransformIdentity, 1, 1);
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [ivImage removeFromSuperview];
            });
        }];
    });
}

@end
