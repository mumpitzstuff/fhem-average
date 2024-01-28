##############################################
# $Id$
# Average computing

package main;
use strict;
use warnings;

##########################
sub
average_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "average_Define";
  $hash->{NotifyFn} = "average_Notify";
  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} = "disable:0,1 " .
                      "disabledForIntervals " .
                      "computeMethod:integral,counter " .
                      "customInterval " .
                      "noaverage:0,1 " .
                      "nominmax:0,1 " .
                      "nohour:0,1 " .
                      "noday:0,1 " .
                      "nomonth:0,1 " .
                      "hideraw:1,0 " .
                      "floatformat:%0.1f,%0.2f";
}


##########################
sub
average_Define($$$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $re, $rest) = split("[ \t]+", $def, 4);

  if(!$re || $rest) {
    my $msg = "wrong syntax: define <name> average device[:event]";
    return $msg;
  }

  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$re$/ };
  return "Bad regexp: $@" if($@);
  $hash->{REGEXP} = $re;
  $hash->{STATE} = "active";
  return undef;
}


sub
avg_setValTime($$$$)
{
  my ($r, $rname, $val, $tn) = @_;
  $r->{$rname}{VAL} = $val;
  $r->{$rname}{TIME} = $tn;
}
##########################
sub
average_Notify($$)
{
  my ($avg, $dev) = @_;
  my $myName = $avg->{NAME};

  return "" if(IsDisabled($myName));

  my $devName = $dev->{NAME};
  my $re = $avg->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  my $tn;
  my $myIdx = $max;

  my $doCounter = (AttrVal($myName, "computeMethod", "integral") eq "counter");
  my $doMMx     = (AttrVal($myName, "nominmax", "0") eq "0");
  my $doAvg     = (AttrVal($myName, "noaverage", "0") eq "0");
  my $doHour    = (AttrVal($myName, "nohour", "0") eq "0");
  my $doDay     = (AttrVal($myName, "noday", "0") eq "0");
  my $doMonth   = (AttrVal($myName, "nomonth", "0") eq "0");
  my $hideRaw   = (AttrVal($myName, "hideraw", "0") eq "0");
  my $ffmt      =  AttrVal($myName, "floatformat", "%0.1f");
  my $custInt   =  AttrVal($myName, "customInterval", 0);
  my $r = $dev->{READINGS};

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];

    ################
    # Filtering
    next if(!defined($s));
    my ($evName, $val) = split(" ", $s, 2); # resets $1
    next if($devName !~ m/^$re$/ && "$devName:$s" !~ m/^$re$/ ||
            $s =~ m/(_avg_|_cum_|_min_|_max_|_cnt_|_int_)/);
    if(defined($1)) {
      my $reArg = $1;
      if(defined($2)) {
        $evName = $1;
        $reArg = $2;
      }
      $val = $reArg if(defined($reArg) && $reArg =~ m/^(-?\d+\.?\d*)/);
    }
    next if(!defined($val) || $val !~ m/^(-?\d+\.?\d*)/);
    $val = $1;

    ################
    # Avg computing
    $evName =~ s/[^A-Za-z\d_\.\-\/]//g;
    $tn = TimeNow() if(!$tn);

    my @dNow = split("[ :-]", $tn);
    my @range = ("hour","day","month","custom");

    for(my $idx = 0; $idx <= 3; $idx++) { # 0:hour 1:day 2:month 3:custom
      my $secNow =  60 * $dNow[4] + $dNow[5];
      $secNow +=  3600 * $dNow[3] if($idx >= 1);
      $secNow += 86400 * $dNow[2] if($idx >= 2);

      my $cumName = "${evName}_cum_" . $range[$idx];
      my $avgName = "${evName}_avg_" . $range[$idx];
      my $minName = "${evName}_min_" . $range[$idx];
      my $maxName = "${evName}_max_" . $range[$idx];
      my $cntName = "${evName}_cnt_" . $range[$idx];
      my $intName = "${evName}_int_" . $range[$idx];

      if(defined($r->{(!$hideRaw ? "." : "") . $cumName})) {
        delete $r->{(!$hideRaw ? "." : "") . $cumName};
      }
      if(defined($r->{(!$hideRaw ? "." : "") . $cntName})) {
        delete $r->{(!$hideRaw ? "." : "") . $cntName};
      }
      if(defined($r->{(!$hideRaw ? "." : "") . $intName})) {
        delete $r->{(!$hideRaw ? "." : "") . $intName};
      }

      $cumName = ($hideRaw ? "." : "") . $cumName;
      $cntName = ($hideRaw ? "." : "") . $cntName;
      $intName = ($hideRaw ? "." : "") . $intName;

      if(((0 == $idx) && (!$doHour)) ||        # deactivate calculation if needed
         ((1 == $idx) && (!$doDay)) ||
         ((2 == $idx) && (!$doMonth)) ||
         ((3 == $idx) && (0 == $custInt))) {
        delete $r->{$cumName} if(defined($r->{$cumName}));      # remove readings
        delete $r->{$cntName} if(defined($r->{$cntName}));
        delete $r->{$avgName} if(defined($r->{$avgName}));
        delete $r->{$minName} if(defined($r->{$minName}));
        delete $r->{$maxName} if(defined($r->{$maxName}));
        delete $r->{$intName} if(defined($r->{$intName}));
        next;
      }

      if ((3 == $idx) && ($custInt > 0) && !defined($r->{$intName})) {
        avg_setValTime($r, $intName, 0, $tn);
      }
      elsif((0 == $custInt) && defined($r->{$intName})) {
        delete $r->{$intName};                                  # reset when switching custom interval off
      }

      if($doCounter && !defined($r->{$cntName})) {
        avg_setValTime($r, $cntName, 1, $tn);
        delete $r->{$cumName} if(defined($r->{$cumName}));      # reset when switching to counter-mode
        delete $r->{$avgName} if(defined($r->{$avgName}));
      }
      elsif(!$doCounter && defined($r->{$cntName})) {
        delete $r->{$cntName};                                  # reset when switching to integral-mode
      }

      if($doMMx && (!defined($r->{$maxName}) || !defined($r->{$minName}))) {
        avg_setValTime($r, $maxName, $val, $tn);
        avg_setValTime($r, $minName, $val, $tn);
      }
      elsif (!$doMMx && (defined($r->{$maxName}) || defined($r->{$minName}))) {
        delete $r->{$maxName} if(defined($r->{$maxName}));      # reset when switching min/max off
        delete $r->{$minName} if(defined($r->{$minName}));
      }

      if(!defined($r->{$cumName}) || ($doAvg && !defined($r->{$avgName}))) {
        my $cum = ($doCounter ? $val : $secNow * $val);
        avg_setValTime($r, $cumName, $cum, $tn);
        avg_setValTime($r, $avgName, $val, $tn) if ($doAvg);
        next;
      }
      elsif (!$doAvg && defined($r->{$avgName})) {
        delete $r->{$avgName};                                  # reset when switching avg off
      }

      my @dLast = split("[ :-]", $r->{$cumName}{TIME});
      my @dInt;
      my $secInt;
      my $secLast =  60 * $dLast[4] + $dLast[5];
      $secLast +=  3600 * $dLast[3] if($idx >= 1);
      $secLast += 86400 * $dLast[2] if($idx >= 2);

      if (($idx == 3) && ($custInt > 0)) {
        @dInt  = split("[ :-]", $r->{$intName}{TIME});
        $secInt = (86400 * $dInt[2]) + (3600 * $dInt[3]) + (60 * $dInt[4]) + $dInt[5];
      }

      if((($idx == 0) && ($dLast[3] == $dNow[3])) ||
         (($idx == 1) && ($dLast[2] == $dNow[2])) ||
         (($idx == 2) && ($dLast[1] == $dNow[1])) ||
         (($idx == 3) && (($secNow - $secInt) <= $custInt))) {  # same hour, day or month or
                                                                # custom interval not reached
        my $cVal = $r->{$cumName}{VAL};
        #$cVal += ($doCounter ? $val : ($secNow - $secLast) * $val);
        if ($doCounter) {
            avg_setValTime($r, $cumName, $cVal + $val, $tn);
        }
        else {
            avg_setValTime($r, $cumName, ($cVal + ($secNow * $val)) / 2, $tn);
        }

        if($doAvg) {
          if($doCounter) {
            avg_setValTime($r, $cntName, $r->{$cntName}{VAL} + 1, $tn);
          }
          my $div = ($secNow ? $secNow : 1);
          my $lVal = sprintf($ffmt, $r->{$cumName}{VAL} / $div);
          avg_setValTime($r, $avgName, $lVal, $tn);
        }

        if($doMMx) {
          avg_setValTime($r, $maxName, sprintf($ffmt,$val), $tn)
                if($r->{$maxName}{VAL} < $val);
          avg_setValTime($r, $minName, sprintf($ffmt,$val), $tn)
                if($r->{$minName}{VAL} > $val);
        }

      }
      elsif (($idx != 3) || (($idx == 3) && ($custInt > 0))) {  # hour, day or month changed or custom interval reached: create events and reset values

        if($doAvg) {
          $dev->{CHANGED}[$myIdx++] = "$avgName: ".$r->{$avgName}{VAL};
          avg_setValTime($r, $cumName, $secNow * $val, $tn);
          avg_setValTime($r, $avgName, $val, $tn);
        }

        if($doCounter) {
          $dev->{CHANGED}[$myIdx++] = "$cumName: ".$r->{$cumName}{VAL};
          avg_setValTime($r, $cumName, 0, $tn);
          avg_setValTime($r, $cntName, 0, $tn) if($doAvg);
        } else {
          avg_setValTime($r, $cumName, $secNow * $val, $tn);
        }

        if($doMMx) {
          $dev->{CHANGED}[$myIdx++] = "$maxName: ".$r->{$maxName}{VAL};
          $dev->{CHANGED}[$myIdx++] = "$minName: ".$r->{$minName}{VAL};
          avg_setValTime($r, $maxName, sprintf($ffmt, $val), $tn);
          avg_setValTime($r, $minName, sprintf($ffmt, $val), $tn);
        }

        if (($idx == 3) && ($custInt > 0)) {
          avg_setValTime($r, $intName, (0 == $r->{$intName}{VAL} ? 1 : 0), $tn);     # reset time of custom interval
        }
      }
    }
  }
  return undef;
}

1;


=pod
=item helper
=item summary    add avarage Readings to arbitrary devices
=item summary_DE berechnet Durchschnittswerte (als Readings)
=begin html

<a id="average"></a>
<h3>average</h3>
<ul>

  Compute additional average, minimum and maximum values for current hour, day and
  month.

  <br>

  <a id="average-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; average &lt;regexp&gt;</code><br>
    <br>
    <ul>
      The syntax for &lt;regexp&gt; is the same as the
      regexp for <a href="#notify">notify</a>.<br>
      If it matches, and the event is of the form "eventname number", then this
      module computes the hourly, daily, monthly and custom interval average, maximum
      and minimum values and sums depending on attribute settings and generates events
      of the form
      <ul>
        &lt;device&gt; &lt;eventname&gt;_avg_hour: &lt;computed_average&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_min_hour: &lt;minimum hour value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_max_hour: &lt;maximum hour value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cum_hour: &lt;sum of the values during the hour&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cnt_hour: &lt;counter during the hour&gt;
      </ul>
      and
      <ul>
        &lt;device&gt; &lt;eventname&gt;_avg_day: &lt;computed_average&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_min_day: &lt;minimum day value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_max_day: &lt;maximum day value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cum_day: &lt;sum of the values during the day&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cnt_day: &lt;counter during the day&gt;
      </ul>
      and
      <ul>
        &lt;device&gt; &lt;eventname&gt;_avg_month: &lt;computed_average&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_min_month: &lt;minimum month value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_max_month: &lt;maximum month value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cum_month: &lt;sum of the values during the month&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cnt_month: &lt;counter during the month&gt;
      </ul>
      and
      <ul>
        &lt;device&gt; &lt;eventname&gt;_avg_custom: &lt;computed_average&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_min_custom: &lt;minimum custom interval value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_max_custom: &lt;maximum custom interval value&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cum_custom: &lt;sum of the values during the custom interval&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_cnt_custom: &lt;counter during the custom interval&gt;
      </ul>
      <ul>
        &lt;device&gt; &lt;eventname&gt;_int_custom: &lt;custom intervall timer&gt;
      </ul>

      at the beginning of the next hour, day, month or custom interval respectively depending on
      attributes defined.<br>
      The current average, minimum, maximum, cumulated values and the counter are stored
      in the device readings depending on attributes defined.
    </ul>
    <br>

    Example:<PRE>
    # Compute the average, minimum and maximum for the temperature events of
    # the ws1 device
    define avg_temp_ws1 average ws1:temperature.*

    # Compute the average, minimum and maximum for each temperature event
    define avg_temp_ws1 average .*:temperature.*

    # Compute the average, minimum and maximum for all temperature and humidity events
    # Events:
    # ws1 temperature: 22.3
    # ws1 humidity: 67.4
    define avg_temp_ws1 average .*:(temperature|humidity).*

    # Compute the same from a combined event. Note: we need two average
    # definitions here, each of them defining the name with the first
    # paranthesis, and the value with the second.
    #
    # Event: ws1 T: 52.3  H: 67.4
    define avg_temp_ws1_t average ws1:(T):.([-\d\.]+).*
    define avg_temp_ws1_h average ws1:.*(H):.([-\d\.]+).*
    </PRE>
  </ul>

  <a id="average-set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a id="average-get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a id="average-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a id="average-attr-computeMethod"></a>
    <li>computeMethod [integral|counter]<br>
      defines how values are added up for the average calculation. This
      attribute can be set to integral or counter.
      The integral mode is meant for measuring continuous values like
      temperature, counter is meant for adding up values, e.g. from a
      feeding unit. In the first case, the time between the events plays an
      important role, in the second case not. Default is integral.</li><br>
    <li>customInterval<br>
      defines a custom interval in seconds (0 = disabled). Value must be
      smaller than a month!</li><br>
    <li>nominmax [0|1]<br>
      don't compute min and max values. Default is 0 (compute min &amp; max).</li><br>
    <li>noaverage [0|1]<br>
      don't compute average values. Default is 0 (compute avarage).</li><br>
    <li>nohour [0|1]<br>
      don't compute hourly values. Default is 0 (compute hourly values).</li><br>
    <li>noday [0|1]<br>
      don't compute daily values. Default is 0 (compute daily values).</li><br>
    <li>nomonth [0|1]<br>
      don't compute monthly values. Default is 0 (compute monthly values).</li><br>
    <li>hideraw [0|1]<br>
      hide raw values. Default is 1 (hide raw values).</li><br>
  </ul>

  <a id="average-events"></a>
  <b>Generated events:</b>
  <ul>
    <li>&lt;eventname&gt;_avg_hour: $avg_hour (only if nohour is set to 0)</li>
    <li>&lt;eventname&gt;_avg_day: $avg_day (only if noday is set to 0)</li>
    <li>&lt;eventname&gt;_avg_month: $avg_month (only if nomonth is set to 0)</li>
    <li>&lt;eventname&gt;_avg_custom: $avg_custom (only if customInterval is not set to 0)</li>
    <li>&lt;eventname&gt;_cum_hour: $cum_hour (only if nohour is set to 0)</li>
    <li>&lt;eventname&gt;_cum_day: $cum_day (only if noday is set to 0)</li>
    <li>&lt;eventname&gt;_cum_month: $cum_month (only if nomonth is set to 0)</li>
    <li>&lt;eventname&gt;_cum_custom: $cum_custom (only if customInterval is not set to 0)</li>
    <li>&lt;eventname&gt;_cnt_hour: $cnt_hour (only if nohour is set to 0 and counter mode is activated)</li>
    <li>&lt;eventname&gt;_cnt_day: $cnt_day (only if noday is set to 0 and counter mode is activated)</li>
    <li>&lt;eventname&gt;_cnt_month: $cnt_month (only if nomonth is set to 0 and counter mode is activated)</li>
    <li>&lt;eventname&gt;_cnt_custom: $cnt_custom (only if customInterval is not set to 0 and counter mode is activated)</li>
    <li>&lt;eventname&gt;_min_hour: $min_hour (only if nohour is set to 0)</li>
    <li>&lt;eventname&gt;_min_day: $min_day (only if noday is set to 0)</li>
    <li>&lt;eventname&gt;_min_month: $min_month (only if nomonth is set to 0)</li>
    <li>&lt;eventname&gt;_min_custom: $min_custom (only if customInterval is not set to 0)</li>
    <li>&lt;eventname&gt;_max_hour: $max_hour (only if nohour is set to 0)</li>
    <li>&lt;eventname&gt;_max_day: $max_day (only if noday is set to 0)</li>
    <li>&lt;eventname&gt;_max_month: $max_month (only if nomonth is set to 0)</li>
    <li>&lt;eventname&gt;_max_custom: $max_custom (only if customInterval is not set to 0)</li>
    <li>&lt;eventname&gt;_int_custom: $int_custom (only if customInterval is not set to 0)</li>
  </ul>
</ul>


=end html
=cut
