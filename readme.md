# Pong (Gameboy)

## Background 
Completed between February 2017 and May 2017, this personal project started with the simple goal to learn some form of Assembly. I thought it would be interesting to learn how the original gameboy worked and to create a very simple, complete game of pong (minus the sounds) in order to better understand what it was like to program for a resource limited platform. 

I used resources from the the excellent Gameboy Assembly Course from Wichita State to learn the basics of the gameboy hardware. The course provided template files which are rehosted here (and modified with my games variables). Unfortunately the link to the course appears to be dead and I fear the resources are now lost. This was the original link, and hopefully they decide to rehost the course: http://cratel.wichita.edu/cratel/ECE238Spr08.

I also rehosted a version of the rgbds gameboy assembler that I know works with the files I've written. I haven't tested the newer versions of rgbds but they should theoretically build the game as well.

The game itself has no AI and is intended to be played with two people. 

## Build Instructions
1. Clone the repo to a local folder on your computer
2. Run the build.bat file
3. Download a gameboy emulator (I use BGB http://bgb.bircd.org/)
4. Open the emulator and select the compiled pong.gb file
5. On the title screen, press start to play the game

## Controls
**Left Paddle**

Up - Up Arrow

Down - Down Arrow

**Right Paddle**

Up - A

Down - B

## Screenshots
![Title Screen](/Screenshots/image1.bmp "Title Screen")
![Right paddle takes the lead](/Screenshots/image2.bmp "Right paddle takes the lead")
![Left paddle comes back](/Screenshots/image3.bmp "Left paddle comes back")
