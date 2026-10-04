import Testing
@testable import DOSBoxerKit

struct BatchMenuReaderTests {
    let boxing = """
        :menu\r
        @echo off\r
        cls\r
        echo Press 1 for ABC Wide World of Sports Boxing w/ SoundBlaster\r
        echo Press 2 for ABC Wide World of Sports Boxing w/ MT-32\r
        echo Press 3 to Quit\r
        choice /C:123 /N Please Choose:\r
        if errorlevel = 3 goto quit\r
        if errorlevel = 2 goto MT32\r
        if errorlevel = 1 goto SB16\r
        :SB16\r
        CONFIG -set "mididevice=default"\r
        copy .\\sb16\\*.* .\\\r
        cls\r
        @vbox\r
        goto quit\r
        :MT32\r
        CONFIG -set "mididevice=mt32"\r
        copy .\\mt32\\*.* .\\\r
        cls\r
        @vbox\r
        goto quit\r
        :quit\r
        exit
        """

    @Test func readsEachOptionsTitleAndCommands() {
        let options = BatchMenuReader.options(in: boxing)
        #expect(options.map(\.title) == ["ABC Wide World of Sports Boxing w/ SoundBlaster",
                                         "ABC Wide World of Sports Boxing w/ MT-32"])
        #expect(options[1].commands == ["CONFIG -set \"mididevice=mt32\"", "copy .\\mt32\\*.* .\\", "vbox"])
    }

    @Test func followsFolderChangesAndCallsBatchFiles() {
        let caves = """
            echo Press 1 for Crystal Caves Vol 1\r
            echo Press 2 for Crystal Caves Vol 2\r
            echo Press 4 to Quit\r
            choice /c:1234 /N Please Choose\r
            if errorlevel = 4 goto quit\r
            if errorlevel = 2 goto cc2\r
            if errorlevel = 1 goto cc1\r
            :cc1\r
            cls\r
            @cd cc1\r
            cc1\r
            cd ..\r
            goto menu\r
            :cc2\r
            @cd cc2\r
            cc2\r
            goto menu
            """
        let options = BatchMenuReader.options(in: caves) { folder, name in
            folder == ["cc2"] && name.lowercased() == "cc2"   // CC2 is a batch file in cc2
        }
        #expect(options.count == 2)
        #expect(options[0].commands == ["cd cc1", "cc1", "cd .."])
        #expect(options[1].commands == ["cd cc2", "CALL cc2"])
    }

    @Test func ignoresScriptsThatArentMenus() {
        #expect(BatchMenuReader.options(in: "@echo off\r\ncd game\r\ngame.exe").isEmpty)
    }
}
