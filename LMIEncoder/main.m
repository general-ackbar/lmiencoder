//
//  main.m
//  LedMatrixImage
//
//  Created by Jonatan Yde on 06/12/2017.
//  Copyright © 2017 Codeninja. All rights reserved.
//

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ColorSpace)
{
	legacy565 = 1,
    rgb888 = 24,
	argb8888 = 32,
    rgb565 = 16,
	duo = 8
};

void printHelp(NSString *exe);
void displayInfo(NSString *file)
{
    NSData *data = [NSData dataWithContentsOfFile: file];
    const unsigned char *bytes = [data bytes];
    
    //TODO: Add field for dynamic header size
    //Header [LMI][0x20=rgb888,0x10=rgb565][width in hex][height in hex][data]
    int headerSize = (int)bytes[4];
    float width, height, fps=0;
    ColorSpace colorSpace = (int)bytes[3] ;
	//backwards compability
	if(colorSpace == legacy565) colorSpace = rgb565;
    width = bytes[5] << 8 |  bytes[6] ;
    height = bytes[7] << 8 |  bytes[8] ;
    BOOL isMultiFrame = NO;
    
    
    
    int index = headerSize;
    int frameLength = (width*height) * (colorSpace / 8);
    //index += frameLength;
    
  
    
    if(data.length-1 > index+frameLength  )
    {
        isMultiFrame = YES;
        if(headerSize > 9) fps = (int) bytes[9];
    }
    
    printf("Printing information about: %s\n", [file cStringUsingEncoding:NSASCIIStringEncoding ]);
    printf("Header size: %i bytes\n", headerSize);
    printf("Width: %i pixels\n", (int)width);
    printf("Height: %i pixels\n", (int)height);
    printf("Frame size: %i bytes\n", (int)frameLength);
    printf("Colorspace: %lu\n", colorSpace);
    printf("Frames: %lu\n", (isMultiFrame ? (data.length-headerSize)/frameLength : 1));
    printf("FPS: %i\n", (int)fps);
}

int main(int argc, char * argv[]) {
    @autoreleasepool {
        
        NSString *inputFile;
        NSString *outputFile;
        BOOL isRGB565 = false;
        int width = 0, height = 0, fps = 0;
        BOOL input_is_encoded = NO;
        BOOL append_to_file = NO;
        BOOL verbose = NO;
		BOOL output_is_c_header = NO;
        
        char c;
        while ((c = getopt (argc, argv, "i:o:rhvacf:")) != -1)
            switch (c)
        {
            case 'i':
                inputFile = [NSString stringWithFormat:@"%s", optarg];
                if([inputFile.pathExtension.lowercaseString isEqualToString:@"lmi"])
                    input_is_encoded = YES;
                break;
            case 'o':
                outputFile = [NSString stringWithFormat:@"%s", optarg];
                if( outputFile.pathExtension.length !=0 )
                    outputFile = [[outputFile stringByDeletingPathExtension] stringByAppendingPathExtension:@"lmi"];
                else if(outputFile.pathExtension.length == 0 && ![outputFile isEqualToString:@"-"] )
                    outputFile = [outputFile stringByAppendingPathExtension:@"lmi"];
                break;
			case 'c':
				output_is_c_header = YES;
				break;
			case 'h':
				printHelp(@"lmiencoder");
				return 0;
			case 'r':
                isRGB565 = YES;
                break;
            case 'a':
                append_to_file = YES;
                break;
            case 'v':
                verbose = YES;
                break;
            case 'f':
                fps = atoi(optarg);
                break;
            case '?':
                if (optopt == 'i' )
                    fprintf (stderr, "Option -%c requires an argument.\n", optopt);
                else if (isprint (optopt))
                    fprintf (stderr, "Unknown option `-%c'.\n", optopt);
                else
                    fprintf (stderr,
                             "Unknown option character `\\x%x'.\n",
                             optopt);
                return 1;
            default:
                abort ();
        }
        
        if(!inputFile)
        {
            printf("Usage: lmiencoder -i <file> [-h][-o][-r][-f][-a][-c].\n");
            return 1;
        }
		
        
        if(input_is_encoded)
        {
            displayInfo(inputFile);
            return 0;
        }
        
        if(!outputFile && ![inputFile isEqualToString:@"-"])
            outputFile = [[[inputFile stringByDeletingPathExtension] lastPathComponent] stringByAppendingPathExtension:@"lmi"];
        else if(!outputFile && [inputFile isEqualToString:@"-"])
            outputFile = @"out.lmi";
        
        NSData *inputData;
        
        if([inputFile isEqualToString:@"-"])
        {
            NSFileHandle *inputHandle = [NSFileHandle fileHandleWithStandardInput];
            NSMutableData *tmpInputData = [[NSMutableData alloc] init];
            NSData *dataBuffer = inputHandle.availableData;
            while(dataBuffer.length > 0)
            {
                [tmpInputData appendData:dataBuffer];
                if(verbose) printf("Data received: %lu\n", (unsigned long)tmpInputData.length);
                dataBuffer = inputHandle.availableData;
            }
            inputData = [NSData dataWithData:tmpInputData];
        }
        else
            inputData = [NSData dataWithContentsOfFile:inputFile];
        
        
        NSImage *inputImage = [[NSImage alloc] initWithData:inputData]; // initWithContentsOfFile:inputFile];
        
        NSBitmapImageRep *inputRep =  [NSBitmapImageRep imageRepWithData:[inputImage TIFFRepresentation]];
        
		width = (int)inputRep.pixelsWide; // inputImage.size.width;
		height = (int)inputRep.pixelsHigh; // inputImage.size.height;
        
        //Byte array to hold image data
        NSMutableData *headerBytes = [[NSMutableData alloc]initWithCapacity:0 ];
        
        //Construct header
        if(fps > 0)
        {
            uint8_t header[10] =  {'L', 'M', 'I', (isRGB565 ? 0x10 : 0x20), 0x0A, (width >> 8) & 0xFF, width & 0xFF, (height >> 8) & 0xFF, height & 0xFF, fps & 0xFF};
            [headerBytes appendBytes: &header length: sizeof(header)];
        } else
        {
            uint8_t header[9] =  {'L', 'M', 'I', (isRGB565 ? 0x10 : 0x20), 0x09, (width >> 8) & 0xFF, width & 0xFF, (height >> 8) & 0xFF, height & 0xFF};
            [headerBytes appendBytes: &header length: sizeof(header)];

        }
        
        
        //Byte array to hold image bytes
        NSMutableData *imageBytes = [[NSMutableData alloc]initWithCapacity:0 ];
        
        for(int y = 0; y < height; y++)
        {
            for(int x = 0; x < width; x++)
            {
                unsigned char currentRedByte, currentBlueByte, currentGreenByte, currentAlphaByte = 0x00;
                uint16_t c_rgb565 = 0;
                
                //Get current color
                NSColor *color = [inputRep colorAtX:x y:y];
                
                //32-bit RGBA values
                currentRedByte = lroundf([color redComponent] * 255);
                currentGreenByte = lroundf([color greenComponent] * 255);
                currentBlueByte = lroundf([color blueComponent] * 255);
                currentAlphaByte = lroundf([color alphaComponent] * 255);
                
                //16-bit RGB values
                c_rgb565 = (currentRedByte & 0b11111000) << 8;
                c_rgb565 = c_rgb565 + ((currentGreenByte & 0b11111100) << 3);
                c_rgb565 = c_rgb565 + ((currentBlueByte) >> 3);
                c_rgb565 = (c_rgb565>>8) | ((c_rgb565 & 0xff) << 8); //Reverse order of bytes
                
                //Append byte to array
                if(isRGB565)
                {
                    [imageBytes appendBytes:&c_rgb565 length:sizeof(c_rgb565)];
                }
                else
                {
                    [imageBytes appendBytes:&currentRedByte length:sizeof(currentRedByte)];
                    [imageBytes appendBytes:&currentGreenByte length:sizeof(currentGreenByte)];
                    [imageBytes appendBytes:&currentBlueByte length:sizeof(currentBlueByte)];
                    [imageBytes appendBytes:&currentAlphaByte length:sizeof(currentAlphaByte)];
                }
            }
        }
        
        if([outputFile isEqualToString: @"-"])
        {
            NSFileHandle *stdout = [NSFileHandle fileHandleWithStandardOutput];
            [stdout writeData: headerBytes];
            [stdout writeData: imageBytes];
            return 0;
        } else if(output_is_c_header)
		{
			const unsigned char *buffer = imageBytes.bytes;
			printf("const unsigned short %s[%lu]  = { ", [[outputFile.lastPathComponent stringByDeletingPathExtension] cStringUsingEncoding:NSUTF8StringEncoding], imageBytes.length/2);
			for(int i = 0; i < imageBytes.length ; i+=2)
			{
				printf("0x%hx", (uint16_t)((buffer[i] << 8) | buffer[i+1]));
				if(i+2 < imageBytes.length)
					printf(", ");
			}
			printf(" };");
			return 0;
		}
        
        //[byteArray writeToFile: [outputName stringByAppendingPathExtension:@"lmi"] atomically:YES];
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:outputFile];
        
        if(append_to_file && fileHandle){
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:imageBytes];
            [fileHandle closeFile];
        } else  {
            [[NSFileManager defaultManager] createFileAtPath:outputFile contents:headerBytes attributes:nil];
            fileHandle = [NSFileHandle fileHandleForWritingAtPath:outputFile];
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:imageBytes];
            [fileHandle closeFile];
        }
        
    }
    return 0;
}

void printHelp(NSString *exe)
{
	printf("Usage: %s -i <file> [-orhvacf].\n", [exe cStringUsingEncoding:NSUTF8StringEncoding]);
	printf("E.g: %s -i input.png -r -o output.lmi.\n", [exe cStringUsingEncoding:NSUTF8StringEncoding]);
	printf("\t-h\tDisplay this help.\n");
	printf("\t-i\tInput file. Must be a bitmap image.\n");
	printf("\t-o\tOutput name.\n");
	printf("\t-v\tBe verbose.\n");
	printf("\t-r\trgb565 format (default is argb8888).\n");
	printf("\t-a\tAppend image to existing LMI.\n");
	printf("\t-f\tSpecify framerate \n");
	printf("\t-c\tPrint as uint_16 c-style array.\n");
}
