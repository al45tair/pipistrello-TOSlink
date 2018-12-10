#include "stdafx.h"
#include <ftd2xx.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <errno.h>

int
main(int argc, char **argv)
{
  FT_STATUS ftStatus;
  FT_HANDLE ftHandle;
  DWORD numDevs;
  DWORD dwBytesWritten;
  DWORD dwBytesReceived;

  ftStatus = FT_CreateDeviceInfoList(&numDevs);

  if (ftStatus != FT_OK) {
    fprintf(stderr,
            "toslink: error %08lx reading device info list\n", ftStatus);
    exit(1);
  }

  FT_DEVICE_LIST_INFO_NODE *devices
    = (FT_DEVICE_LIST_INFO_NODE *)malloc(sizeof(*devices) * numDevs);

  ftStatus = FT_GetDeviceInfoList(devices, &numDevs);

  if (ftStatus != FT_OK) {
    fprintf(stderr,
            "toslink: error %08lx reading device info list\n", ftStatus);
    exit(1);
  }

  unsigned deviceNdx;
  bool foundDevice = false;

  if (argc >= 2) {
    for (unsigned n = 0; n < numDevs; ++n) {
      if (strcmp (devices[n].Description, argv[1]) == 0
          || strcmp (devices[n].SerialNumber, argv[1]) == 0) {
        foundDevice = true;
        deviceNdx = n;
        break;
      }
    }
  }

  if (!foundDevice || argc != 2) {
    printf("Found %lu devices.\n", numDevs);

    for (unsigned n = 0; n < numDevs; ++n) {
      printf("%u: %s (%s, %08lx)\n", n,
             devices[n].Description,
             devices[n].SerialNumber,
             devices[n].LocId);
    }

    free(devices);

    return 0;
  }

  printf("Using device %s (%s, %08lx)\n",
         devices[deviceNdx].Description,
         devices[deviceNdx].SerialNumber,
         devices[deviceNdx].LocId);

  ftStatus = FT_Open(deviceNdx, &ftHandle);

  if (ftStatus != FT_OK) {
    printf("Error %08lx opening device\n", ftStatus);
    free(devices);
    return 1;
  }

  ftStatus = FT_SetTimeouts(ftHandle, 1000, 1000);

  if (ftStatus != FT_OK) {
    printf("Error %08lx setting timeouts\n", ftStatus);
    free(devices);
    return 1;
  }

  printf("Ready\n");

  char linebuf[256];
  static unsigned char databuf[65536];

  while (true) {
    printf("> ");

    char *line = fgets (linebuf, sizeof(linebuf), stdin);

    if (!line)
      break;

    /* Remove trailing \n */
    char *ptr = strchr(line, '\n');
    if (ptr)
      *ptr = '\0';

    if (strcmp(line, "exit") == 0 || strcmp(line, "quit") == 0)
      break;

    if (strcmp(line, "purge") == 0) {
      ftStatus = FT_Purge(ftHandle, FT_PURGE_RX|FT_PURGE_TX);
      if (ftStatus != FT_OK)
	printf("Error %08lx\n", ftStatus);
      else
	printf("OK\n");
    } else if (strncmp(line, "purge ", 6) == 0) {
      DWORD dwMask = 0;

      if (strcmp(line + 6, "rx") == 0)
	dwMask = FT_PURGE_RX;
      else if (strcmp(line + 6, "tx") == 0)
	dwMask = FT_PURGE_TX;
      else if (strcmp(line + 6, "all") == 0)
	dwMask = FT_PURGE_RX | FT_PURGE_TX;

      ftStatus = FT_Purge(ftHandle, dwMask);
      if (ftStatus != FT_OK)
	printf("Error %08lx\n", ftStatus);
      else
	printf("OK\n");
    } else if (strncmp(line, "read ", 5) == 0) {
      unsigned long addr, count;
      char *ptr, *next;

      ptr = line + 5;
      addr = strtoul(ptr, &next, 0);

      if (next == ptr) {
	printf("Syntax error - expected address\n");
      } else {
	ptr = next;
	while (isspace(*ptr))
	  ++ptr;

	count = strtoul(ptr, &next, 0);

	if (next == ptr || count == 0 || count > sizeof(databuf))
	  count = 64;

	unsigned long cmd[3] = {
	  _byteswap_ulong(1),
	  _byteswap_ulong(addr),
	  _byteswap_ulong(count)
	};
	ftStatus = FT_Write(ftHandle, cmd, sizeof(cmd), &dwBytesWritten);

	if (ftStatus == FT_OK) {
	  ftStatus = FT_Read(ftHandle, databuf, count * sizeof(unsigned),
			     &dwBytesReceived);
	}

	if (ftStatus != FT_OK) {
	  printf("Error %08lx\n", ftStatus);
	} else {
	  for (unsigned n = 0; n < dwBytesReceived; ++n) {
	    if ((n & 0x0f) == 0) {
	      if (n)
		printf("\n");
	      printf("%08x: ", addr + n);
	    }
	    printf("%02x ", databuf[n]);
	  }
	  printf("\n");
	}
      }
    } else if (strncmp(line, "save ", 5) == 0) {
      unsigned long addr, count;
      char *ptr, *next;

      ptr = line + 5;
      addr = strtoul(ptr, &next, 0);

      if (next == ptr) {
	printf("Syntax error - expected address\n");
      } else {
	ptr = next;
	while (isspace(*ptr))
	  ++ptr;

	count = strtoul(ptr, &next, 0);

	if (next == ptr) {
	  printf("Syntax error - expected count\n");
	} else if (count == 0) {
	  printf("No bytes to save\n");
	} else if (count > sizeof(databuf)) {
	  printf("Too many bytes to save\n");
	} else {
	  ptr = next;
	  while (isspace(*ptr))
	    ++ptr;

	  if (!*ptr) {
	    printf("Syntax error - expected filename\n");
	  } else {
	    unsigned long cmd[3] = {
	      _byteswap_ulong(1),
	      _byteswap_ulong(addr),
	      _byteswap_ulong(count)
	    };
	    ftStatus = FT_Write(ftHandle, cmd, sizeof(cmd), &dwBytesWritten);

	    unsigned char *pbuf = databuf;
	    size_t todo = count * sizeof(unsigned);
	    while (ftStatus == FT_OK && todo) {
	      size_t chunk = todo > 32768 ? 32768 : todo;
	      ftStatus = FT_Read(ftHandle, pbuf, chunk,
				 &dwBytesReceived);
	      if (ftStatus == FT_OK) {
		pbuf += dwBytesReceived;
		todo -= dwBytesReceived;
	      }
	    }

	    if (ftStatus != FT_OK) {
	      printf("Error %08lx\n", ftStatus);
	    } else {
	      FILE *fp = fopen(ptr, "wb");

	      if (!fp) {
		printf("Unable to open file - %s\n", strerror(errno));
	      } else {
		fwrite(databuf, sizeof(unsigned), count, fp);
		fclose(fp);
	      }
	    }
	  }
	}
      }
    } else if (strncmp(line, "capture ", 8) == 0) {
      unsigned long count;
      char *ptr, *next;

      ptr = line + 8;
      count = strtoul(ptr, &next, 0);

      if (next == ptr) {
	printf("Syntax error\n");
      } else {
	unsigned long cmd[2] = {
	  _byteswap_ulong(3),
	  _byteswap_ulong(count)
	};

	ftStatus = FT_Write(ftHandle, cmd, sizeof(cmd), &dwBytesWritten);

	if (ftStatus != FT_OK) {
	  printf("Error %08lx\n", ftStatus);
	} else {
	  printf("Capture started\n");
	}
      }
    } else if (strcmp(line, "status") == 0) {
      unsigned long cmd = _byteswap_ulong(4);

      ftStatus = FT_Write(ftHandle, &cmd, sizeof(cmd), &dwBytesWritten);

      if (ftStatus != FT_OK) {
	printf("Error %08lx\n", ftStatus);
      } else {
	unsigned long response[2];

	ftStatus = FT_Read(ftHandle, response,
			   sizeof(response), &dwBytesReceived);

	if (ftStatus != FT_OK) {
	  printf("Error %08lx\n", ftStatus);
	} else if (dwBytesReceived != sizeof(response)) {
	  printf("Unexpected status response length\n");
	} else {
	  response[0] = _byteswap_ulong(response[0]);
	  response[1] = _byteswap_ulong(response[1]);

	  printf("%s, %s, %lu frames left\n",
		 response[0] & 1 ? "Synchronized" : "LOS",
		 response[0] & 2 ? "Done" : "Running",
		 response[1]);
	}
      }
    } else if (strcmp(line, "chstatus") == 0) {
      unsigned long cmd = _byteswap_ulong(5);

      ftStatus = FT_Write(ftHandle, &cmd, sizeof(cmd), &dwBytesWritten);

      if (ftStatus != FT_OK) {
	printf("Error %08lx\n", ftStatus);
      } else {
	unsigned char response[24];

	ftStatus = FT_Read(ftHandle, response,
			   sizeof(response), &dwBytesReceived);

	if (ftStatus != FT_OK) {
	  printf("Error %08lx\n", ftStatus);
	} else if (dwBytesReceived != sizeof(response)) {
	  printf("Unexpected channel status response length\n");
	} else {
	  for (unsigned n = 0; n < 24; ++n)
	    printf("%02x ", response[n]);
	  printf("\n");
	}
      }
    }
  }

  FT_Close(ftHandle);
  free(devices);

  return 0;
}
