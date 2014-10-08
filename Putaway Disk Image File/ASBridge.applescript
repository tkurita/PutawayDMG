script ASBridge
	property parent : class "NSObject"
	property FinderSelection : module
    property loader : boot (module loader) for me
    property appDelegate : missing value
    
    on finderSelectionWithMountPoint_(mount_point)
        --log "start finderSelectionWithMountPoint_"
        tell FinderSelection's make_for_item()
            --set_chooser_for_folder()
            --set_prompt_message("Choose a disk of a disk image")
            set_use_chooser(false)
            --set_default_location((mount_point as text) as POSIX file)
            set_use_insertion_location(true)
            set a_list to get_selection()
        end tell
        --log a_list
        set result_list to {}
        repeat with an_item in a_list
            set contents of an_item to an_item's POSIX path
        end repeat
        return a_list
    end finderSelectionWithMountPoint_
    
    on selectionInFinder()
        tell FinderSelection's make_for_item()
            set_use_chooser(false)
            set_use_insertion_location(true)
            set a_list to get_selection()
        end tell
        if a_list is missing value then
            return {}
        end if
        set result_list to {}
        repeat with an_item in a_list
            set contents of an_item to an_item's POSIX path
        end repeat
        return a_list
    end selectionInFinder
end script