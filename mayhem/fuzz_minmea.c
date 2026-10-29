#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "minmea.h"

static void exercise_time(const struct minmea_date *d, const struct minmea_time *t)
{
    struct tm tm;
    struct timespec ts;
    (void)minmea_getdatetime(&tm, d, t);
    (void)minmea_gettime(&ts, d, t);
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    if (size == 0)
        return -1;

    char *s = malloc(size + 1);
    if (!s)
        return -1;
    memcpy(s, data, size);
    s[size] = '\0';

    (void)minmea_checksum(s);
    (void)minmea_check(s, true);
    (void)minmea_check(s, false);

    char talker[3];
    (void)minmea_talker_id(talker, s);

    enum minmea_sentence_id id = minmea_sentence_id(s, false);
    (void)minmea_sentence_id(s, true);
    (void)minmea_sentence(id);

    switch (id) {
    case MINMEA_SENTENCE_GBS: {
        struct minmea_sentence_gbs f;
        (void)minmea_parse_gbs(&f, s);
        break;
    }
    case MINMEA_SENTENCE_GGA: {
        struct minmea_sentence_gga f;
        if (minmea_parse_gga(&f, s)) {
            (void)minmea_tocoord(&f.latitude);
            (void)minmea_tocoord(&f.longitude);
            (void)minmea_tofloat(&f.altitude);
        }
        break;
    }
    case MINMEA_SENTENCE_GLL: {
        struct minmea_sentence_gll f;
        if (minmea_parse_gll(&f, s)) {
            (void)minmea_tocoord(&f.latitude);
            (void)minmea_tocoord(&f.longitude);
        }
        break;
    }
    case MINMEA_SENTENCE_GSA: {
        struct minmea_sentence_gsa f;
        (void)minmea_parse_gsa(&f, s);
        break;
    }
    case MINMEA_SENTENCE_GST: {
        struct minmea_sentence_gst f;
        (void)minmea_parse_gst(&f, s);
        break;
    }
    case MINMEA_SENTENCE_GSV: {
        struct minmea_sentence_gsv f;
        (void)minmea_parse_gsv(&f, s);
        break;
    }
    case MINMEA_SENTENCE_RMC: {
        struct minmea_sentence_rmc f;
        if (minmea_parse_rmc(&f, s)) {
            exercise_time(&f.date, &f.time);
            (void)minmea_tocoord(&f.latitude);
            (void)minmea_tocoord(&f.longitude);
            (void)minmea_tofloat(&f.speed);
        }
        break;
    }
    case MINMEA_SENTENCE_VTG: {
        struct minmea_sentence_vtg f;
        (void)minmea_parse_vtg(&f, s);
        break;
    }
    case MINMEA_SENTENCE_ZDA: {
        struct minmea_sentence_zda f;
        if (minmea_parse_zda(&f, s))
            exercise_time(&f.date, &f.time);
        break;
    }
    default:
        break;
    }

    free(s);
    return 0;
}
