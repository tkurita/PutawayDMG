//
//  main.m
//  Putaway Disk Image File
//
//  Created by 栗田 哲郎 on 2014/10/03.
//  Copyright (c) 2014年 栗田 哲郎. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <AppleScriptObjC/AppleScriptObjC.h>

int main(int argc, char *argv[])
{
    [[NSBundle mainBundle] loadAppleScriptObjectiveCScripts];
    return NSApplicationMain(argc, (const char **)argv);
}
