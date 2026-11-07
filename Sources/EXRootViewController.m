#import "EXRootViewController.h"
#import "EXMetadata.h"
#import "EXDevice.h"
#import "EXEnhancer.h"
#import <PhotosUI/PhotosUI.h>
#import <Photos/Photos.h>
#import <CoreLocation/CoreLocation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>
#import <os/log.h>

static os_log_t EXEditLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.melon.exifone", "edit");
    });
    return log;
}

static NSString *EXShortHashOfFile(NSURL *url) {
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
    if (data.length == 0) {
        return [[[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:8];
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:8];
    for (int i = 0; i < 4; i++) {
        [hex appendFormat:@"%02X", digest[i]];
    }
    return hex;
}

@interface EXRootViewController () <PHPickerViewControllerDelegate, CLLocationManagerDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;

@property (nonatomic, strong) UIView *previewCard;
@property (nonatomic, strong) UIImageView *previewView;
@property (nonatomic, strong) UILabel *previewPlaceholder;

@property (nonatomic, strong) UIButton *pickButton;
@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) UIStackView *deviceStack;
@property (nonatomic, strong) UIStackView *originalStack;
@property (nonatomic, strong) UIStackView *resultStack;
@property (nonatomic, strong) UIStackView *resultBody;

@property (nonatomic, strong) UISwitch *deviceSwitch;
@property (nonatomic, strong) UISwitch *timeSwitch;
@property (nonatomic, strong) UISwitch *locationSwitch;
@property (nonatomic, strong) UISwitch *distanceCustomSwitch;
@property (nonatomic, strong) UISegmentedControl *timeModeControl;
@property (nonatomic, strong) UISegmentedControl *distanceControl;
@property (nonatomic, strong) UISegmentedControl *formatControl;
@property (nonatomic, strong) UISwitch *enhanceSwitch;
@property (nonatomic, strong) UISegmentedControl *enhanceScaleControl;
@property (nonatomic, strong) UIView *enhanceScaleRow;
@property (nonatomic, strong) UISwitch *nameSwitch;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIView *nameFieldRow;
@property (nonatomic, strong) UIDatePicker *datePicker;
@property (nonatomic, strong) UIView *timeFixedRow;
@property (nonatomic, strong) UIView *locationRangeRow;
@property (nonatomic, strong) UIView *distanceSwitchRow;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, assign) NSUInteger previewIndex;

@property (nonatomic, strong) NSArray<NSURL *> *sourceURLs;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastLocation;
@property (nonatomic, strong) CLLocation *pickedLocation;
@property (nonatomic, copy) NSString *pickedLocationName;
@property (nonatomic, strong) NSTimer *clockTimer;
@end

@implementation EXRootViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"jexi";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildInterface];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    [self refreshDeviceCard];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.locationManager requestWhenInUseAuthorization];
    [self.locationManager startUpdatingLocation];
    [self startClock];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.clockTimer invalidate];
    self.clockTimer = nil;
}

- (void)startClock {
    if (self.clockTimer != nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshDeviceCard];
    }];
}

#pragma mark - 界面

- (void)buildInterface {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] init];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 16;
    self.contentStack.alignment = UIStackViewAlignmentFill;
    [self.scrollView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:18],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-18],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-24],
    ]];

    // 预览
    self.previewCard = [[UIView alloc] init];
    self.previewCard.backgroundColor = [UIColor tertiarySystemFillColor];
    self.previewCard.layer.cornerRadius = 14;
    self.previewCard.clipsToBounds = YES;

    self.previewView = [[UIImageView alloc] init];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.contentMode = UIViewContentModeScaleAspectFit;
    [self.previewCard addSubview:self.previewView];

    self.previewPlaceholder = [[UILabel alloc] init];
    self.previewPlaceholder.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewPlaceholder.text = @"还没有选择照片";
    self.previewPlaceholder.font = [UIFont systemFontOfSize:14];
    self.previewPlaceholder.textColor = [UIColor secondaryLabelColor];
    self.previewPlaceholder.numberOfLines = 0;
    self.previewPlaceholder.textAlignment = NSTextAlignmentCenter;
    [self.previewCard addSubview:self.previewPlaceholder];

    [NSLayoutConstraint activateConstraints:@[
        [self.previewCard.heightAnchor constraintEqualToConstant:200],
        [self.previewView.topAnchor constraintEqualToAnchor:self.previewCard.topAnchor],
        [self.previewView.leadingAnchor constraintEqualToAnchor:self.previewCard.leadingAnchor],
        [self.previewView.trailingAnchor constraintEqualToAnchor:self.previewCard.trailingAnchor],
        [self.previewView.bottomAnchor constraintEqualToAnchor:self.previewCard.bottomAnchor],
        [self.previewPlaceholder.centerXAnchor constraintEqualToAnchor:self.previewCard.centerXAnchor],
        [self.previewPlaceholder.centerYAnchor constraintEqualToAnchor:self.previewCard.centerYAnchor],
        [self.previewPlaceholder.leadingAnchor constraintEqualToAnchor:self.previewCard.leadingAnchor constant:16],
        [self.previewPlaceholder.trailingAnchor constraintEqualToAnchor:self.previewCard.trailingAnchor constant:-16],
    ]];

    self.pageControl = [[UIPageControl alloc] init];
    self.pageControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageControl.hidesForSinglePage = YES;
    self.pageControl.userInteractionEnabled = NO;
    [self.previewCard addSubview:self.pageControl];
    [NSLayoutConstraint activateConstraints:@[
        [self.pageControl.centerXAnchor constraintEqualToAnchor:self.previewCard.centerXAnchor],
        [self.pageControl.bottomAnchor constraintEqualToAnchor:self.previewCard.bottomAnchor constant:-4],
    ]];

    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                   action:@selector(previewSwiped:)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.previewCard addGestureRecognizer:swipeLeft];

    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(previewSwiped:)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [self.previewCard addGestureRecognizer:swipeRight];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                           action:@selector(previewLongPressed:)];
    [self.previewCard addGestureRecognizer:longPress];

    [self.contentStack addArrangedSubview:self.previewCard];

    // 选照片
    self.pickButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *pickConfig = [UIButtonConfiguration filledButtonConfiguration];
    pickConfig.title = @"选择照片（可多选）";
    pickConfig.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    self.pickButton.configuration = pickConfig;
    [self.pickButton addTarget:self action:@selector(pickPhotos) forControlEvents:UIControlEventTouchUpInside];
    [self.contentStack addArrangedSubview:self.pickButton];

    // 待写入数据
    [self.contentStack addArrangedSubview:[self sectionLabel:@"将要写入的真实设备数据"]];
    self.deviceStack = [self cardStack];
    [self.contentStack addArrangedSubview:self.deviceStack];

    // 选项
    [self.contentStack addArrangedSubview:[self sectionLabel:@"要改哪些"]];

    self.deviceSwitch = [self makeSwitchOn:YES];
    self.timeSwitch = [self makeSwitchOn:YES];
    self.locationSwitch = [self makeSwitchOn:YES];

    UIStackView *options = [self cardStack];
    [options addArrangedSubview:[self switchRow:@"设备信息" detail:@"机型、系统版本；镜头与曝光参数在区间内随机" control:self.deviceSwitch]];

    [options addArrangedSubview:[self separator]];
    [options addArrangedSubview:[self nameSection]];

    [options addArrangedSubview:[self separator]];
    [options addArrangedSubview:[self switchRow:@"更新时间" detail:@"模式见下；关闭则不写入时间" control:self.timeSwitch]];
    [options addArrangedSubview:[self buildTimeModeRow]];
    self.timeFixedRow = [self buildTimeFixedRow];
    [options addArrangedSubview:self.timeFixedRow];

    [options addArrangedSubview:[self separator]];
    [options addArrangedSubview:[self switchRow:@"真实定位" detail:@"关闭则抹掉照片原有位置" control:self.locationSwitch]];
    [options addArrangedSubview:[self locationSourceRow]];

    [options addArrangedSubview:[self separator]];
    [options addArrangedSubview:[self formatRow]];
    [options addArrangedSubview:[self separator]];
    [options addArrangedSubview:[self enhanceSection]];
    [self.contentStack addArrangedSubview:options];

    [self.timeSwitch addTarget:self action:@selector(timeSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [self.locationSwitch addTarget:self action:@selector(locationSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [self updateTimeRows];

    // 执行
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *applyConfig = [UIButtonConfiguration filledButtonConfiguration];
    applyConfig.title = @"一键修改并保存到相册";
    applyConfig.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    self.applyButton.configuration = applyConfig;
    self.applyButton.enabled = NO;
    [self.applyButton addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentStack addArrangedSubview:self.applyButton];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.text = @"选一张或多张照片，然后一键替换 EXIF。";
    [self.contentStack addArrangedSubview:self.statusLabel];

    // 原图
    [self.contentStack addArrangedSubview:[self sectionLabel:@"原图信息"]];
    self.originalStack = [self cardStack];
    [self.contentStack addArrangedSubview:self.originalStack];
    [self fillStack:self.originalStack withRows:@[] emptyText:@"还没有选择照片"];

    // 结果
    self.resultStack = [[UIStackView alloc] init];
    self.resultStack.axis = UILayoutConstraintAxisVertical;
    self.resultStack.spacing = 8;
    [self.resultStack addArrangedSubview:[self sectionLabel:@"修改后信息"]];
    self.resultBody = [self cardStack];
    [self.resultStack addArrangedSubview:self.resultBody];
    self.resultStack.hidden = YES;
    [self.contentStack addArrangedSubview:self.resultStack];

    UILabel *note = [[UILabel alloc] init];
    note.font = [UIFont systemFontOfSize:12];
    note.textColor = [UIColor tertiaryLabelColor];
    note.numberOfLines = 0;
    note.text = @"写入这台设备上真实可读的数据：机型、系统版本、时间与时区、定位，以及按机型匹配的镜头与曝光参数。批量修改时所有照片共用同一个位置，时间在所选范围内各不相同。照片以新文件保存到相册，原图不动。";
    [self.contentStack addArrangedSubview:note];
}

- (UILabel *)sectionLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    label.textColor = [UIColor labelColor];
    return label;
}

- (UIStackView *)cardStack {
    UIStackView *card = [[UIStackView alloc] init];
    card.axis = UILayoutConstraintAxisVertical;
    card.spacing = 10;
    card.layoutMarginsRelativeArrangement = YES;
    card.layoutMargins = UIEdgeInsetsMake(14, 14, 14, 14);
    card.backgroundColor = [UIColor secondarySystemBackgroundColor];
    card.layer.cornerRadius = 14;
    return card;
}

- (UIView *)separator {
    UIView *line = [[UIView alloc] init];
    line.backgroundColor = [UIColor separatorColor];
    [line.heightAnchor constraintEqualToConstant:0.5].active = YES;
    return line;
}

- (UISwitch *)makeSwitchOn:(BOOL)on {
    UISwitch *control = [[UISwitch alloc] init];
    control.on = on;
    return control;
}

- (UIView *)switchRow:(NSString *)title detail:(NSString *)detail control:(UISwitch *)control {
    UIStackView *text = [[UIStackView alloc] init];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:16];
    [text addArrangedSubview:titleLabel];

    UILabel *detailLabel = [[UILabel alloc] init];
    detailLabel.text = detail;
    detailLabel.font = [UIFont systemFontOfSize:12];
    detailLabel.textColor = [UIColor secondaryLabelColor];
    detailLabel.numberOfLines = 0;
    [text addArrangedSubview:detailLabel];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[text, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}

- (UIView *)buildTimeModeRow {
    UILabel *title = [[UILabel alloc] init];
    title.text = @"时间模式";
    title.font = [UIFont systemFontOfSize:13];
    title.textColor = [UIColor secondaryLabelColor];

    self.timeModeControl = [[UISegmentedControl alloc] initWithItems:@[@"现在", @"指定"]];
    self.timeModeControl.selectedSegmentIndex = 0;
    [self.timeModeControl addTarget:self action:@selector(timeModeChanged)
                   forControlEvents:UIControlEventValueChanged];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.timeModeControl]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 6;
    return row;
}

- (UIView *)buildTimeFixedRow {
    UILabel *title = [[UILabel alloc] init];
    title.text = @"指定时间";
    title.font = [UIFont systemFontOfSize:16];
    [title setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

    self.datePicker = [[UIDatePicker alloc] init];
    self.datePicker.datePickerMode = UIDatePickerModeDateAndTime;
    self.datePicker.preferredDatePickerStyle = UIDatePickerStyleCompact;
    self.datePicker.date = [NSDate date];
    [self.datePicker addTarget:self action:@selector(datePicked) forControlEvents:UIControlEventValueChanged];

    UIButton *now = [UIButton buttonWithType:UIButtonTypeSystem];
    [now setTitle:@"现在" forState:UIControlStateNormal];
    [now addTarget:self action:@selector(useNowTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.datePicker, now]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    self.timeFixedRow = row;
    return row;
}

- (UIView *)locationSourceRow {
    UILabel *title = [[UILabel alloc] init];
    title.text = @"位置来源";
    title.font = [UIFont systemFontOfSize:13];
    title.textColor = [UIColor secondaryLabelColor];

    UISegmentedControl *sourceControl = [[UISegmentedControl alloc] initWithItems:@[@"当前定位", @"附近随机"]];
    sourceControl.selectedSegmentIndex = 0;
    sourceControl.tag = 2001;
    [sourceControl addTarget:self action:@selector(locationSourceChanged)
            forControlEvents:UIControlEventValueChanged];

    UIButton *shuffle = [UIButton buttonWithType:UIButtonTypeSystem];
    [shuffle setTitle:@"换一个" forState:UIControlStateNormal];
    [shuffle addTarget:self action:@selector(shuffleNearbyTapped) forControlEvents:UIControlEventTouchUpInside];
    [shuffle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *controlRow = [[UIStackView alloc] initWithArrangedSubviews:@[sourceControl, shuffle]];
    controlRow.axis = UILayoutConstraintAxisHorizontal;
    controlRow.alignment = UIStackViewAlignmentCenter;
    controlRow.spacing = 10;

    UILabel *rangeTitle = [[UILabel alloc] init];
    rangeTitle.text = @"随机范围";
    rangeTitle.font = [UIFont systemFontOfSize:13];
    rangeTitle.textColor = [UIColor secondaryLabelColor];

    self.distanceControl = [[UISegmentedControl alloc] initWithItems:@[@"100 m", @"500 m", @"1 km", @"5 km"]];
    self.distanceControl.selectedSegmentIndex = 1;
    [self.distanceControl addTarget:self action:@selector(distanceChanged)
                   forControlEvents:UIControlEventValueChanged];

    UIStackView *rangeStack = [[UIStackView alloc] initWithArrangedSubviews:@[rangeTitle, self.distanceControl]];
    rangeStack.axis = UILayoutConstraintAxisVertical;
    rangeStack.spacing = 6;
    rangeStack.hidden = YES;
    self.locationRangeRow = rangeStack;

    self.distanceCustomSwitch = [self makeSwitchOn:YES];
    [self.distanceCustomSwitch addTarget:self action:@selector(distanceCustomChanged)
                        forControlEvents:UIControlEventValueChanged];
    UIView *customRow = [self switchRow:@"自定义随机范围" detail:@"关闭时固定在 500 米内" control:self.distanceCustomSwitch];
    customRow.hidden = YES;
    self.distanceSwitchRow = customRow;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, controlRow, customRow, rangeStack]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 6;
    return row;
}

- (void)distanceCustomChanged {
    [self updateLocationRows];
    [self refreshDeviceCard];
}

- (void)updateLocationRows {
    UISegmentedControl *source = [self locationSourceControlRef];
    BOOL nearby = (source.selectedSegmentIndex == 1) && self.locationSwitch.isOn;
    self.distanceSwitchRow.hidden = !nearby;
    self.locationRangeRow.hidden = !(nearby && self.distanceCustomSwitch.isOn);
}

- (UIView *)enhanceSection {
    self.enhanceSwitch = [self makeSwitchOn:NO];
    [self.enhanceSwitch addTarget:self action:@selector(enhanceChanged)
                 forControlEvents:UIControlEventValueChanged];
    UIView *row = [self switchRow:@"超清增强" detail:@"放大并锐化，长边最大 8192 像素" control:self.enhanceSwitch];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"放大倍数";
    title.font = [UIFont systemFontOfSize:13];
    title.textColor = [UIColor secondaryLabelColor];

    self.enhanceScaleControl = [[UISegmentedControl alloc] initWithItems:@[@"2×", @"3×", @"4×"]];
    self.enhanceScaleControl.selectedSegmentIndex = 0;

    UIStackView *scaleRow = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.enhanceScaleControl]];
    scaleRow.axis = UILayoutConstraintAxisVertical;
    scaleRow.spacing = 6;
    scaleRow.hidden = YES;
    self.enhanceScaleRow = scaleRow;

    UIStackView *container = [[UIStackView alloc] initWithArrangedSubviews:@[row, scaleRow]];
    container.axis = UILayoutConstraintAxisVertical;
    container.spacing = 8;
    return container;
}

- (void)enhanceChanged {
    self.enhanceScaleRow.hidden = !self.enhanceSwitch.isOn;
}

- (UIView *)nameSection {
    self.nameSwitch = [self makeSwitchOn:NO];
    [self.nameSwitch addTarget:self action:@selector(nameSwitchChanged)
              forControlEvents:UIControlEventValueChanged];
    UIView *row = [self switchRow:@"自定义文件名" detail:@"关闭则用系统默认命名" control:self.nameSwitch];

    UITextField *field = [[UITextField alloc] init];
    field.placeholder = @"留空则 IMG_ + 图片 hash";
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.font = [UIFont systemFontOfSize:15];
    [field.heightAnchor constraintEqualToConstant:36].active = YES;
    self.nameField = field;

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"收起键盘" forState:UIControlStateNormal];
    [done addTarget:self action:@selector(dismissKeyboard) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *fieldRow = [[UIStackView alloc] initWithArrangedSubviews:@[field, done]];
    fieldRow.axis = UILayoutConstraintAxisVertical;
    fieldRow.spacing = 6;
    fieldRow.hidden = YES;
    self.nameFieldRow = fieldRow;

    UIStackView *container = [[UIStackView alloc] initWithArrangedSubviews:@[row, fieldRow]];
    container.axis = UILayoutConstraintAxisVertical;
    container.spacing = 8;
    return container;
}

- (void)nameSwitchChanged {
    self.nameFieldRow.hidden = !self.nameSwitch.isOn;
    if (self.nameSwitch.isOn) {
        [self.nameField becomeFirstResponder];
    } else {
        [self.view endEditing:YES];
    }
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (UIView *)formatRow {
    UILabel *title = [[UILabel alloc] init];
    title.text = @"输出格式";
    title.font = [UIFont systemFontOfSize:16];

    UILabel *detail = [[UILabel alloc] init];
    detail.text = @"HEIF 体积更小；换格式会重新编码";
    detail.font = [UIFont systemFontOfSize:12];
    detail.textColor = [UIColor secondaryLabelColor];
    detail.numberOfLines = 0;

    self.formatControl = [[UISegmentedControl alloc] initWithItems:@[@"原格式", @"JPEG", @"HEIF"]];
    self.formatControl.selectedSegmentIndex = 0;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail, self.formatControl]];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 6;
    return row;
}

- (UISegmentedControl *)locationSourceControlRef {
    return (UISegmentedControl *)[self.view viewWithTag:2001];
}

- (void)updateTimeRows {
    BOOL timeOn = self.timeSwitch.isOn;
    BOOL fixedMode = (self.timeModeControl.selectedSegmentIndex == 1);
    self.timeFixedRow.hidden = !(timeOn && fixedMode);
}

- (void)timeModeChanged {
    [self updateTimeRows];
    [self refreshDeviceCard];
}

- (void)timeSwitchChanged {
    self.datePicker.enabled = self.timeSwitch.isOn;
    [self updateTimeRows];
    [self refreshDeviceCard];
}

- (void)datePicked {
    self.timeSwitch.on = YES;
    [self updateTimeRows];
    [self refreshDeviceCard];
}

- (void)useNowTapped {
    self.datePicker.date = [NSDate date];
    self.timeSwitch.on = YES;
    [self updateTimeRows];
    [self refreshDeviceCard];
    [self setStatus:@"时间已设为现在。"];
}

- (void)locationSwitchChanged {
    UISegmentedControl *source = [self locationSourceControlRef];
    source.enabled = self.locationSwitch.isOn;
    self.distanceControl.enabled = self.locationSwitch.isOn;
    if (!self.locationSwitch.isOn) {
        self.pickedLocation = nil;
        self.pickedLocationName = nil;
        source.selectedSegmentIndex = 0;
    }
    [self updateLocationRows];
    [self refreshDeviceCard];
}

- (void)locationSourceChanged {
    UISegmentedControl *source = [self locationSourceControlRef];
    [self updateLocationRows];
    if (source.selectedSegmentIndex == 0) {
        self.pickedLocation = nil;
        self.pickedLocationName = nil;
        [self refreshDeviceCard];
        [self setStatus:@"位置用当前定位。"];
        return;
    }
    [self generateNearbyLocation];
}

- (void)distanceChanged {
    [self refreshDeviceCard];
}

- (double)maxDistance {
    if (!self.distanceCustomSwitch.isOn) {
        return 500.0;
    }
    switch (self.distanceControl.selectedSegmentIndex) {
        case 0: return 100.0;
        case 1: return 500.0;
        case 2: return 1000.0;
        default: return 5000.0;
    }
}

- (void)shuffleNearbyTapped {
    UISegmentedControl *source = [self locationSourceControlRef];
    self.locationSwitch.on = YES;
    source.enabled = YES;
    self.distanceControl.enabled = YES;
    source.selectedSegmentIndex = 1;
    [self updateLocationRows];
    [self generateNearbyLocation];
}

- (void)generateNearbyLocation {
    CLLocation *base = [self freshLocation];
    if (base == nil) {
        [self setStatus:@"还没拿到当前定位，等几秒再点一次「换一个」。"];
        UISegmentedControl *source = [self locationSourceControlRef];
        source.selectedSegmentIndex = 0;
        return;
    }
    double maxDistance = [self maxDistance];
    double minDistance = MAX(20.0, maxDistance * 0.15);
    double distance = minDistance + (double)arc4random_uniform((uint32_t)(maxDistance - minDistance + 1));
    double bearing = ((double)arc4random_uniform(3600) / 10.0) * M_PI / 180.0;
    double lat1 = base.coordinate.latitude * M_PI / 180.0;
    double lon1 = base.coordinate.longitude * M_PI / 180.0;
    double angular = distance / 6371000.0;
    double lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing));
    double lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1),
                               cos(angular) - sin(lat1) * sin(lat2));

    self.pickedLocation = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat2 * 180.0 / M_PI,
                                                                                           lon2 * 180.0 / M_PI)
                                                        altitude:base.altitude
                                              horizontalAccuracy:MAX(5.0, base.horizontalAccuracy)
                                                verticalAccuracy:MAX(5.0, base.verticalAccuracy)
                                                       timestamp:[NSDate date]];
    self.pickedLocationName = [NSString stringWithFormat:@"附近约 %.0f 米", distance];
    [self refreshDeviceCard];
    [self setStatus:[NSString stringWithFormat:@"已随机选一个约 %.0f 米外的位置，点「换一个」可重选。", distance]];
}

- (UIView *)rowWithKey:(NSString *)key value:(NSString *)value {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisVertical;
    row.spacing = 2;

    UILabel *keyLabel = [[UILabel alloc] init];
    keyLabel.text = key;
    keyLabel.font = [UIFont systemFontOfSize:12];
    keyLabel.textColor = [UIColor secondaryLabelColor];
    [row addArrangedSubview:keyLabel];

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.text = value;
    valueLabel.font = [UIFont systemFontOfSize:15];
    valueLabel.numberOfLines = 0;
    [row addArrangedSubview:valueLabel];
    return row;
}

- (void)fillStack:(UIStackView *)stack withRows:(NSArray<NSDictionary<NSString *, NSString *> *> *)rows
        emptyText:(NSString *)emptyText {
    for (UIView *view in [stack.arrangedSubviews copy]) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (rows.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = emptyText;
        empty.font = [UIFont systemFontOfSize:13];
        empty.textColor = [UIColor secondaryLabelColor];
        empty.numberOfLines = 0;
        [stack addArrangedSubview:empty];
        return;
    }
    BOOL first = YES;
    for (NSDictionary<NSString *, NSString *> *row in rows) {
        if (!first) {
            [stack addArrangedSubview:[self separator]];
        }
        [stack addArrangedSubview:[self rowWithKey:row[@"key"] value:row[@"value"]]];
        first = NO;
    }
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.text = text;
}

#pragma mark - 设备卡片

- (void)refreshDeviceCard {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *rows = [NSMutableArray array];
    [rows addObject:@{@"key": @"机型", @"value": self.deviceSwitch.isOn
                          ? [NSString stringWithFormat:@"Apple %@ (%@)", [EXDevice marketingName], [EXDevice machineIdentifier]]
                          : @"不改"}];
    [rows addObject:@{@"key": @"系统", @"value": self.deviceSwitch.isOn ? [EXDevice systemDescription] : @"不改"}];
    [rows addObject:@{@"key": @"时间", @"value": [self timeDescription]}];
    [rows addObject:@{@"key": @"位置", @"value": self.locationSwitch.isOn ? [self locationDescription]
                                                                       : @"不改（并抹掉原位置）"}];
    if (self.sourceURLs.count > 1) {
        [rows addObject:@{@"key": @"批量", @"value": [NSString stringWithFormat:@"共 %lu 张，每张时间不同",
                                                     (unsigned long)self.sourceURLs.count]}];
    }
    [self fillStack:self.deviceStack withRows:rows emptyText:@""];
}

- (NSString *)timeDescription {
    if (!self.timeSwitch.isOn) {
        return @"不改";
    }
    NSString *base = nil;
    if (self.timeModeControl.selectedSegmentIndex == 0) {
        base = @"现在";
    } else {
        NSDate *date = self.datePicker.date ?: [NSDate date];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone localTimeZone];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        base = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:date],
                [EXDevice offsetStringForDate:date]];
    }
    return base;
}

- (NSString *)locationDescription {
    if (self.pickedLocation != nil) {
        CLLocation *picked = self.pickedLocation;
        NSString *name = self.pickedLocationName.length > 0 ? self.pickedLocationName : @"附近随机";
        return [NSString stringWithFormat:@"%@ · %.6f, %.6f", name,
                picked.coordinate.latitude, picked.coordinate.longitude];
    }
    CLLocation *location = [self freshLocation];
    if (location == nil) {
        CLAuthorizationStatus status = self.locationManager.authorizationStatus;
        if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
            return @"未授权定位（在设置里允许后可写入真实位置）";
        }
        return @"正在定位…";
    }
    return [NSString stringWithFormat:@"%.6f, %.6f  (±%.0f m)",
            location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy];
}

- (CLLocation *)freshLocation {
    if (self.lastLocation == nil) {
        return nil;
    }
    if ([[NSDate date] timeIntervalSinceDate:self.lastLocation.timestamp] > 120) {
        return nil;
    }
    return self.lastLocation;
}

#pragma mark - 定位回调

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        [manager startUpdatingLocation];
    }
    [self refreshDeviceCard];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (location != nil) {
        self.lastLocation = location;
        [self refreshDeviceCard];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [self refreshDeviceCard];
}

#pragma mark - 选图

- (void)pickPhotos {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 0;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) {
        return;
    }
    [self setStatus:[NSString stringWithFormat:@"正在载入 %lu 张照片…", (unsigned long)results.count]];

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    for (PHPickerResult *result in results) {
        NSItemProvider *provider = result.itemProvider;
        dispatch_group_enter(group);
        [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier
                                        completionHandler:^(NSURL *url, NSError *error) {
            if (url != nil) {
                NSString *extension = url.pathExtension.length > 0 ? url.pathExtension : @"jpg";
                NSString *name = [NSString stringWithFormat:@"src-%@.%@", [NSUUID UUID].UUIDString, extension];
                NSURL *destination = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
                if ([[NSFileManager defaultManager] copyItemAtURL:url toURL:destination error:NULL]) {
                    @synchronized (urls) {
                        [urls addObject:destination];
                    }
                }
            }
            dispatch_group_leave(group);
        }];
    }
    __weak typeof(self) weakSelf = self;
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (urls.count == 0) {
            [weakSelf setStatus:@"照片载入失败，重新选一次试试。"];
            return;
        }
        [weakSelf useSourceURLs:[urls copy]];
    });
}

- (void)useSourceURLs:(NSArray<NSURL *> *)urls {
    self.sourceURLs = urls;
    self.applyButton.enabled = (urls.count > 0);
    self.resultStack.hidden = YES;
    [self updateTimeRows];
    [self showPhotoAtIndex:0];
    [self refreshDeviceCard];
    [self setStatus:[NSString stringWithFormat:@"已选 %lu 张，左右滑动查看，长按可删除。",
                     (unsigned long)urls.count]];
}

- (void)showPhotoAtIndex:(NSUInteger)index {
    if (self.sourceURLs.count == 0) {
        return;
    }
    if (index >= self.sourceURLs.count) {
        index = self.sourceURLs.count - 1;
    }
    self.previewIndex = index;
    NSURL *url = self.sourceURLs[index];
    UIImage *image = [UIImage imageWithContentsOfFile:url.path];
    self.previewView.image = image;
    self.previewPlaceholder.hidden = (image != nil);
    self.pageControl.numberOfPages = self.sourceURLs.count;
    self.pageControl.currentPage = index;
    self.pageControl.hidden = (self.sourceURLs.count <= 1);

    NSDictionary *properties = [EXMetadata propertiesAtURL:url];
    [self fillStack:self.originalStack
           withRows:[EXMetadata summaryRowsFromProperties:properties]
          emptyText:@"读不出这张照片的信息"];
}

- (void)previewSwiped:(UISwipeGestureRecognizer *)gesture {
    if (self.sourceURLs.count <= 1) {
        return;
    }
    NSInteger next = (NSInteger)self.previewIndex;
    if (gesture.direction == UISwipeGestureRecognizerDirectionLeft) {
        next += 1;
    } else {
        next -= 1;
    }
    if (next < 0) {
        next = (NSInteger)self.sourceURLs.count - 1;
    }
    if (next >= (NSInteger)self.sourceURLs.count) {
        next = 0;
    }
    [self showPhotoAtIndex:(NSUInteger)next];
}

- (void)previewLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || self.sourceURLs.count == 0) {
        return;
    }
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"第 %lu 张（共 %lu 张）",
                                  (unsigned long)(self.previewIndex + 1),
                                  (unsigned long)self.sourceURLs.count]
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除这张照片"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction *action) {
        [weakSelf removePreviewedPhoto];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.previewCard;
    sheet.popoverPresentationController.sourceRect = self.previewCard.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)removePreviewedPhoto {
    if (self.previewIndex >= self.sourceURLs.count) {
        return;
    }
    NSMutableArray<NSURL *> *urls = [self.sourceURLs mutableCopy];
    [urls removeObjectAtIndex:self.previewIndex];

    if (urls.count == 0) {
        self.sourceURLs = @[];
        self.previewView.image = nil;
        self.previewPlaceholder.text = @"还没有选择照片";
        self.previewPlaceholder.hidden = NO;
        self.pageControl.hidden = YES;
        self.applyButton.enabled = NO;
        self.resultStack.hidden = YES;
        [self fillStack:self.originalStack withRows:@[] emptyText:@"还没有选择照片"];
        [self updateTimeRows];
        [self refreshDeviceCard];
        [self setStatus:@"照片已全部移除。"];
        return;
    }

    self.sourceURLs = urls;
    [self updateTimeRows];
    NSUInteger index = MIN(self.previewIndex, urls.count - 1);
    [self showPhotoAtIndex:index];
    [self refreshDeviceCard];
    [self setStatus:[NSString stringWithFormat:@"已删除，剩 %lu 张。", (unsigned long)urls.count]];
}

#pragma mark - 写入

- (NSDate *)dateForIndex:(NSUInteger)index total:(NSUInteger)total {
    if (!self.timeSwitch.isOn) {
        return nil;
    }
    if (self.timeModeControl.selectedSegmentIndex == 1) {
        return self.datePicker.date ?: [NSDate date];
    }
    return [NSDate date];
}

- (void)applyTapped {
    if (self.sourceURLs.count == 0) {
        [self setStatus:@"先选照片。"];
        return;
    }
    EXWriteOptions options = EXWriteNone;
    if (self.deviceSwitch.isOn) {
        options |= EXWriteDevice;
    }
    if (self.timeSwitch.isOn) {
        options |= EXWriteTime;
    }
    CLLocation *location = nil;
    if (self.locationSwitch.isOn) {
        location = self.pickedLocation ?: [self freshLocation];
        if (location == nil) {
            [self setStatus:@"还没拿到定位，稍等几秒再试，或关掉「真实定位」。"];
            return;
        }
        options |= EXWriteLocation;
    }
    if (options == EXWriteNone) {
        [self setStatus:@"至少打开一项要改的内容。"];
        return;
    }

    EXOutputFormat format = EXOutputFormatKeep;
    NSString *extension = @"jpg";
    if (self.formatControl.selectedSegmentIndex == 1) {
        format = EXOutputFormatJPEG;
        extension = @"jpg";
    } else if (self.formatControl.selectedSegmentIndex == 2) {
        format = EXOutputFormatHEIF;
        extension = @"heic";
    } else {
        NSString *sourceExtension = self.sourceURLs.firstObject.pathExtension;
        extension = sourceExtension.length > 0 ? sourceExtension : @"jpg";
    }

    NSArray<NSURL *> *sources = self.sourceURLs;
    NSMutableArray *dates = [NSMutableArray arrayWithCapacity:sources.count];
    for (NSUInteger index = 0; index < sources.count; index++) {
        NSDate *date = [self dateForIndex:index total:sources.count];
        [dates addObject:date ?: [NSNull null]];
    }
    BOOL enhance = self.enhanceSwitch.isOn;
    CGFloat enhanceScale = [@[@2.0, @3.0, @4.0][self.enhanceScaleControl.selectedSegmentIndex] doubleValue];
    [self setStatus:enhance
        ? [NSString stringWithFormat:@"正在超清处理 %lu 张…", (unsigned long)sources.count]
        : [NSString stringWithFormat:@"正在处理 %lu 张…", (unsigned long)sources.count]];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray<NSURL *> *outputs = [NSMutableArray array];
        NSError *firstError = nil;
        for (NSUInteger index = 0; index < sources.count; index++) {
            NSURL *source = sources[index];
            id dateEntry = dates[index];
            NSDate *date = [dateEntry isKindOfClass:[NSDate class]] ? dateEntry : nil;

            NSURL *input = source;
            EXOutputFormat writeFormat = format;
            NSString *writeExtension = extension;
            if (enhance) {
                NSString *enhanceExtension = (format == EXOutputFormatKeep)
                    ? (source.pathExtension.length > 0 ? source.pathExtension : @"jpg")
                    : extension;
                NSString *enhanceName = [NSString stringWithFormat:@"enh-%@.%@",
                                         [NSUUID UUID].UUIDString, enhanceExtension];
                NSURL *enhanced = [NSURL fileURLWithPath:
                                   [NSTemporaryDirectory() stringByAppendingPathComponent:enhanceName]];
                NSError *enhanceError = nil;
                if (![EXEnhancer upscaleURL:source toURL:enhanced scale:enhanceScale
                               maxDimension:8192 error:&enhanceError]) {
                    firstError = enhanceError;
                    break;
                }
                input = enhanced;
                writeFormat = EXOutputFormatKeep;
                writeExtension = enhanceExtension;
            }

            NSString *name = [NSString stringWithFormat:@"out-%@.%@", [NSUUID UUID].UUIDString, writeExtension];
            NSURL *output = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
            NSError *error = nil;
            if (![EXMetadata writeSourceURL:input toDestination:output options:options
                                   location:location date:date format:writeFormat error:&error]) {
                firstError = error;
                break;
            }
            [outputs addObject:output];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (firstError != nil) {
                os_log(EXEditLog(), "批量: 写文件失败 %{public}@", firstError.localizedDescription);
                [weakSelf setStatus:[NSString stringWithFormat:@"修改失败：%@", firstError.localizedDescription]];
                return;
            }
            if (outputs.count > 0) {
                NSDictionary *properties = [EXMetadata propertiesAtURL:outputs.lastObject];
                [weakSelf fillStack:weakSelf.resultBody
                           withRows:[EXMetadata summaryRowsFromProperties:properties]
                          emptyText:@"没有写入任何信息"];
                weakSelf.resultStack.hidden = NO;
            }
            [weakSelf beginSaving:outputs];
        });
    });
}

- (void)beginSaving:(NSArray<NSURL *> *)outputs {
    __weak typeof(self) weakSelf = self;
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                              handler:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
                [weakSelf setStatus:@"没有相册写入权限：设置 ▸ 隐私与安全性 ▸ 照片 里允许后重试。"];
                return;
            }
            [weakSelf saveOutputs:outputs atIndex:0];
        });
    }];
}

- (void)saveOutputs:(NSArray<NSURL *> *)outputs atIndex:(NSUInteger)index {
    if (index >= outputs.count) {
        [self setStatus:[NSString stringWithFormat:@"已保存 %lu 张新照片到相册，原图未改动。",
                         (unsigned long)outputs.count]];
        return;
    }
    [self setStatus:[NSString stringWithFormat:@"正在保存 %lu/%lu…", (unsigned long)(index + 1),
                     (unsigned long)outputs.count]];

    NSString *customBase = nil;
    if (self.nameSwitch.isOn) {
        customBase = [self.nameField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (customBase.length == 0) {
            customBase = [@"IMG_" stringByAppendingString:EXShortHashOfFile(outputs[index])];
        }
    }

    __weak typeof(self) weakSelf = self;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        PHAssetResourceCreationOptions *resourceOptions = nil;
        if (customBase.length > 0) {
            resourceOptions = [[PHAssetResourceCreationOptions alloc] init];
            NSString *extension = outputs[index].pathExtension;
            resourceOptions.originalFilename = extension.length > 0
                ? [customBase stringByAppendingPathExtension:extension] : customBase;
        }
        [request addResourceWithType:PHAssetResourceTypePhoto fileURL:outputs[index] options:resourceOptions];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!success) {
                os_log(EXEditLog(), "保存第 %lu 张失败: %{public}@", (unsigned long)(index + 1),
                       error.localizedDescription ?: @"未知");
                [weakSelf setStatus:[NSString stringWithFormat:@"第 %lu 张保存失败：%@",
                                     (unsigned long)(index + 1), error.localizedDescription]];
                return;
            }
            [weakSelf saveOutputs:outputs atIndex:index + 1];
        });
    }];
}

@end
