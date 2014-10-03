--
--  AppDelegate.applescript
--  Putaway Disk Image File
--
--  Created by 栗田 哲郎 on 2014/10/03.
--  Copyright (c) 2014年 栗田 哲郎. All rights reserved.
--

script AppDelegate
	property parent : class "NSObject"
	
	on applicationWillFinishLaunching_(aNotification)
		-- Insert code here to initialize your application before any files are opened 
	end applicationWillFinishLaunching_
	
	on applicationShouldTerminate_(sender)
		-- Insert code here to do any housekeeping before your application quits 
		return current application's NSTerminateNow
	end applicationShouldTerminate_
	
end script